import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../providers/chat_provider.dart';
import '../providers/file_provider.dart';
import '../utils/node_id_utils.dart';
import 'database_service.dart';
import 'identity_service.dart';
import 'queue_service.dart';
import 'notification_service.dart';

typedef MediaRetrySender = Future<FileSendResult> Function({
  required String toPeerId,
  required String fileId,
  required String filename,
  required MessageType messageType,
  required String? localPath,
});

typedef MediaCleanup = Future<void> Function({
  String? fileId,
  String? localPath,
});

typedef ReadReceiptSender = Future<bool> Function({
  required String toPeerId,
  required String msgId,
});

/// Service for chat operations
class ChatService {
  static final ChatService instance = ChatService._();

  final _uuid = const Uuid();
  final _messageController = StreamController<Message>.broadcast();

  // Native message ID -> Local UUID mapping
  final Map<String, String> _nativeMsgIdToLocalId = {};
  final Map<String, String> _localIdToNativeMsgId = {};

  // ChatProvider reference (set after initialization)
  ChatProvider? _chatProvider;

  // Subscriptions
  StreamSubscription? _messageSubscription;
  StreamSubscription? _ackSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _reactionSubscription;
  StreamSubscription? _deleteSubscription;
  StreamSubscription? _editSubscription;

  // Disappearing messages cleanup timer
  Timer? _disappearingMessagesTimer;
  Timer? _readReceiptRetryTimer;
  bool _flushingReadReceipts = false;

  // Default disappearing messages setting (from settings)
  int? _defaultDisappearingSeconds;

  ReadReceiptSender? _readReceiptSender;
  final Map<String, _PendingReadReceipt> _pendingReadReceipts = {};

  static const Duration _readReceiptRetryInterval = Duration(seconds: 5);
  static const Duration _readReceiptBaseBackoff = Duration(seconds: 3);
  static const Duration _readReceiptMaxBackoff = Duration(minutes: 1);
  static const int _readReceiptMaxAttempts = 8;

  ChatService._() {
    // Start cleanup timer for disappearing messages
    _startDisappearingMessagesCleanup();
  }

  /// Set default disappearing messages duration from settings
  void setDefaultDisappearingSeconds(int? seconds) {
    _defaultDisappearingSeconds = seconds;
  }

  /// Start periodic cleanup of expired disappearing messages
  void _startDisappearingMessagesCleanup() {
    _disappearingMessagesTimer?.cancel();
    // Check every 30 seconds for expired messages
    _disappearingMessagesTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupExpiredMessages(),
    );
  }

  /// Delete expired disappearing messages
  Future<void> _cleanupExpiredMessages() async {
    try {
      final deleted = await DatabaseService.instance.deleteExpiredMessages();
      if (deleted > 0) {
        debugPrint(
            'ChatService: Deleted $deleted expired disappearing messages');
      }
    } catch (e) {
      debugPrint('ChatService: Error cleaning up expired messages: $e');
    }
  }

  /// Connect to ChatProvider for FFI messaging
  void connectProvider(ChatProvider provider) {
    _chatProvider = provider;

    // Cancel existing subscriptions
    _messageSubscription?.cancel();
    _ackSubscription?.cancel();
    _typingSubscription?.cancel();
    _reactionSubscription?.cancel();
    _deleteSubscription?.cancel();
    _editSubscription?.cancel();

    // Subscribe to incoming messages
    _messageSubscription =
        provider.messageStream.listen(_handleIncomingMessage);
    _ackSubscription = provider.ackStream.listen(_handleAck);
    _typingSubscription = provider.typingStream.listen(_handleTyping);
    _reactionSubscription = provider.reactionStream.listen(_handleReaction);
    _deleteSubscription = provider.deleteStream.listen(_handleDelete);
    _editSubscription = provider.editStream.listen(_handleEdit);

    unawaited(_restoreNativeMessageMappings());

    debugPrint('ChatService: Connected to ChatProvider');
  }

  Future<void> _restoreNativeMessageMappings() async {
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query(
        'messages',
        columns: ['id', 'native_msg_id'],
        where: 'native_msg_id IS NOT NULL',
      );

      for (final row in rows) {
        final localId = row['id'] as String;
        final nativeMsgId = row['native_msg_id'] as String;
        _nativeMsgIdToLocalId[nativeMsgId] = localId;
        _localIdToNativeMsgId[localId] = nativeMsgId;
      }
      debugPrint('ChatService: Restored ${rows.length} native message IDs');
    } catch (e) {
      debugPrint('ChatService: Failed to restore native message IDs: $e');
    }
  }

  /// Disconnect from ChatProvider
  void disconnectProvider() {
    _messageSubscription?.cancel();
    _ackSubscription?.cancel();
    _typingSubscription?.cancel();
    _reactionSubscription?.cancel();
    _deleteSubscription?.cancel();
    _editSubscription?.cancel();
    _chatProvider = null;
  }

  /// Stream of new messages
  Stream<Message> get messageStream => _messageController.stream;

  /// Emit a message to the stream (for other services to use)
  void emitMessage(Message message) {
    _messageController.add(message);
  }

  Future<void> _emitMessageById(String messageId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      _messageController.add(Message.fromMap(rows.first));
    }
  }

  /// Get all conversations
  Future<List<Conversation>> getConversations() async {
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery('''
      SELECT c.*, m.content as last_message_content, m.timestamp as last_message_time, m.sender_id as last_message_sender
      FROM conversations c
      LEFT JOIN messages m ON m.id = (
        SELECT id FROM messages
        WHERE conversation_id = c.id
        ORDER BY timestamp DESC
        LIMIT 1
      )
      ORDER BY c.is_pinned DESC, c.last_activity_at DESC
    ''');

    return rows.map((row) => Conversation.fromMap(row)).toList();
  }

  /// Get conversation by ID
  Future<Conversation?> getConversation(String id) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  /// Get or create direct conversation with peer
  Future<Conversation> getOrCreateDirectConversation(String peerId) async {
    final db = await DatabaseService.instance.database;

    // Check if exists
    final existing = await db.query(
      'conversations',
      where: 'peer_id = ? AND type = ?',
      whereArgs: [peerId, ConversationType.direct.index],
    );

    if (existing.isNotEmpty) {
      final conv = Conversation.fromMap(existing.first);

      // If conversation exists but has no display name, try to get it from contacts
      if (conv.displayName == null) {
        final contactRows = await db.query(
          'contacts',
          columns: ['display_name'],
          where: 'node_id = ?',
          whereArgs: [peerId],
        );
        if (contactRows.isNotEmpty &&
            contactRows.first['display_name'] != null) {
          final displayName = contactRows.first['display_name'] as String;
          // Update the conversation with the contact's display name
          await db.update(
            'conversations',
            {'display_name': displayName},
            where: 'id = ?',
            whereArgs: [conv.id],
          );
          return conv.copyWith(displayName: displayName);
        }
      }
      return conv;
    }

    // Look up contact's display name
    String? contactDisplayName;
    final contactRows = await db.query(
      'contacts',
      columns: ['display_name'],
      where: 'node_id = ?',
      whereArgs: [peerId],
    );
    if (contactRows.isNotEmpty && contactRows.first['display_name'] != null) {
      contactDisplayName = contactRows.first['display_name'] as String;
    }

    // Create new conversation with contact's display name
    final id = _uuid.v4();
    final conversation = Conversation(
      id: id,
      type: ConversationType.direct,
      peerId: peerId,
      displayName: contactDisplayName,
      lastActivityAt: DateTime.now(),
    );

    await db.insert('conversations', conversation.toMap());
    return conversation;
  }

  /// Get messages for conversation
  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map((row) => Message.fromMap(row)).toList().reversed.toList();
  }

  /// Send message (text or file)
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String? replyToId,
    MessageType type = MessageType.text,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      throw StateError('No identity');
    }

    // Get conversation to find peer ID
    final convRows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    if (convRows.isEmpty) {
      throw StateError('Conversation not found');
    }
    final conversation = Conversation.fromMap(convRows.first);

    final message = Message(
      id: _uuid.v4(),
      conversationId: conversationId,
      senderId: identity.nodeId,
      type: type,
      content: content,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      replyToId: replyToId,
      isOutgoing: true,
    );

    // Save to database (transaction ensures atomicity of insert + update)
    try {
      await db.transaction((txn) async {
        await txn.insert('messages', message.toMap());
        await txn.update(
          'conversations',
          {
            'last_activity_at': message.timestamp.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [conversationId],
        );
      });
    } catch (e) {
      debugPrint('ChatService: Database error saving message: $e');
      return message.copyWith(status: MessageStatus.failed);
    }

    // Try to send via native chat (only for text messages - files use FileProvider)
    Message resultMessage;
    if (_chatProvider != null &&
        conversation.peerId != null &&
        type == MessageType.text) {
      // Get native reply-to ID if replying
      String? nativeReplyToId;
      if (replyToId != null) {
        nativeReplyToId = _localIdToNativeMsgId[replyToId];
      }

      final result = await _chatProvider!.sendText(
        toPeerId: conversation.peerId!,
        text: content,
        replyToMsgId: nativeReplyToId,
        localMsgId: message.id, // Track for ACK timeout
      );

      if (result.success && result.nativeMsgId != null) {
        // Store mapping
        _nativeMsgIdToLocalId[result.nativeMsgId!] = message.id;
        _localIdToNativeMsgId[message.id] = result.nativeMsgId!;

        resultMessage = message.copyWith(status: MessageStatus.sent);
        await db.update(
          'messages',
          {
            'status': MessageStatus.sent.index,
            'native_msg_id': result.nativeMsgId!,
          },
          where: 'id = ?',
          whereArgs: [message.id],
        );
      } else {
        // Send failed - mark as failed and enqueue for retry
        resultMessage = message.copyWith(status: MessageStatus.failed);
        await db.update(
          'messages',
          {'status': MessageStatus.failed.index},
          where: 'id = ?',
          whereArgs: [message.id],
        );

        // Enqueue for automatic retry
        await QueueService.instance.enqueue(
          messageId: message.id,
          recipientId: conversation.peerId!,
          data: utf8.encode(content),
        );
        debugPrint(
            'ChatService: Send failed, queued for retry: ${result.error}');
      }
    } else {
      if (type.isMedia) {
        // Media/file messages are transferred by FileProvider. The chat row is
        // local metadata and is completed by file transfer callbacks.
        resultMessage = message.copyWith(status: MessageStatus.sending);
        debugPrint('ChatService: Media message saved, transfer in progress');
      } else if (conversation.peerId != null) {
        // No native chat available for text - mark as failed and enqueue
        resultMessage = message.copyWith(status: MessageStatus.failed);
        await db.update(
          'messages',
          {'status': MessageStatus.failed.index},
          where: 'id = ?',
          whereArgs: [message.id],
        );

        // Enqueue for automatic retry when connection is available
        await QueueService.instance.enqueue(
          messageId: message.id,
          recipientId: conversation.peerId!,
          data: utf8.encode(content),
        );
        debugPrint(
            'ChatService: No native chat available, message queued for retry');
      } else {
        // No peer ID - mark as pending (group messages, etc.)
        resultMessage = message.copyWith(status: MessageStatus.pending);
        await db.update(
          'messages',
          {'status': MessageStatus.pending.index},
          where: 'id = ?',
          whereArgs: [message.id],
        );
        debugPrint('ChatService: No peer ID, message saved as pending');
      }
    }

    _messageController.add(resultMessage);
    return resultMessage;
  }

  /// Handle incoming file offer (creates a pending file message in conversation)
  Future<void> handleFileRequest(FileRequest request) async {
    final db = await DatabaseService.instance.database;
    final normalizedPeerId = _normalizePeerId(request.fromPeerId);
    final conversation = await getOrCreateDirectConversation(normalizedPeerId);
    final fileSize = request.formattedSize;
    final content = jsonEncode({
      'fileId': request.fileId,
      'filename': request.filename,
      'size': fileSize,
      'pending': true,
    });

    final existing = await db.query(
      'messages',
      where: 'conversation_id = ? AND is_outgoing = 0 AND content LIKE ?',
      whereArgs: [conversation.id, '%${request.fileId}%'],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final message = Message(
      id: _uuid.v4(),
      conversationId: conversation.id,
      senderId: normalizedPeerId,
      type: MessageType.file,
      content: content,
      timestamp: DateTime.now(),
      status: MessageStatus.pending,
      isOutgoing: false,
    );

    await db.insert('messages', message.toMap());
    await db.update(
      'conversations',
      {
        'last_activity_at': message.timestamp.millisecondsSinceEpoch,
        'unread_count': conversation.unreadCount + 1,
      },
      where: 'id = ?',
      whereArgs: [conversation.id],
    );

    _messageController.add(message);
    await _showMessageNotification(
      conversationId: conversation.id,
      senderNodeId: normalizedPeerId,
      messageContent: 'File request: ${request.filename}',
    );
  }

  /// Handle received file (creates or updates file message in conversation)
  Future<void> handleReceivedFile({
    required String fromPeerId,
    required String filename,
    required String fileSize,
    required String fileId,
    String? localPath,
  }) async {
    final db = await DatabaseService.instance.database;

    // Normalize peer ID format (convert 64-char hex with trailing zeros to UUID)
    final normalizedPeerId = _normalizePeerId(fromPeerId);
    debugPrint(
        'ChatService: Normalized peer ID: $fromPeerId -> $normalizedPeerId');

    // Get or create conversation with sender
    final conversation = await getOrCreateDirectConversation(normalizedPeerId);

    // Detect if this is a voice message (check filename pattern and extension)
    final isVoiceMessage = filename.startsWith('voice_') &&
        (filename.endsWith('.m4a') ||
            filename.endsWith('.aac') ||
            filename.endsWith('.opus'));

    // Create message content based on type
    final String fileContent;
    final MessageType messageType;

    if (isVoiceMessage) {
      // Voice message - extract duration from size estimate (rough: 8kbps = 1KB/s)
      final sizeBytes = _parseSizeToBytes(fileSize);
      final estimatedDuration = (sizeBytes / 8000).round(); // Rough estimate
      fileContent = jsonEncode({
        'fileId': fileId,
        'duration': estimatedDuration,
        'filename': filename,
        if (localPath != null) 'localPath': localPath,
      });
      messageType = MessageType.audio;
      debugPrint('ChatService: Received voice message: $filename ($fileSize)');
    } else {
      // Regular file
      fileContent = jsonEncode({
        'fileId': fileId,
        'filename': filename,
        'size': fileSize,
        if (localPath != null) 'localPath': localPath,
      });
      messageType = MessageType.file;
      debugPrint('ChatService: Received file: $filename ($fileSize)');
    }

    final existingRows = await db.query(
      'messages',
      where: 'conversation_id = ? AND is_outgoing = 0 AND content LIKE ?',
      whereArgs: [conversation.id, '%$fileId%'],
      limit: 1,
    );
    final Message message;
    final bool insertedNewMessage;

    if (existingRows.isNotEmpty) {
      message = Message.fromMap(existingRows.first).copyWith(
        type: messageType,
        content: fileContent,
        status: MessageStatus.delivered,
      );
      insertedNewMessage = false;
      await db.update(
        'messages',
        message.toMap(),
        where: 'id = ?',
        whereArgs: [message.id],
      );
    } else {
      message = Message(
        id: _uuid.v4(),
        conversationId: conversation.id,
        senderId: normalizedPeerId,
        type: messageType,
        content: fileContent,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        isOutgoing: false,
      );
      insertedNewMessage = true;
      await db.insert('messages', message.toMap());
    }

    // Update conversation
    await db.update(
      'conversations',
      {
        'last_activity_at': message.timestamp.millisecondsSinceEpoch,
        'unread_count': insertedNewMessage
            ? conversation.unreadCount + 1
            : conversation.unreadCount,
      },
      where: 'id = ?',
      whereArgs: [conversation.id],
    );

    // Emit to stream
    _messageController.add(message);

    await _showMessageNotification(
      conversationId: conversation.id,
      senderNodeId: normalizedPeerId,
      messageContent: isVoiceMessage ? 'Voice message' : 'File: $filename',
    );

    debugPrint('ChatService: Received file "$filename" from $fromPeerId');
  }

  /// Mark an outgoing file/media message complete once FileProvider finishes.
  Future<void> handleFileTransferCompleted(
    String fileId, {
    String? localPath,
  }) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'messages',
      where: 'is_outgoing = 1 AND content LIKE ?',
      whereArgs: ['%$fileId%'],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final existing = Message.fromMap(rows.first);
    final content = _contentWithLocalPath(existing.content, localPath);
    final message = existing.copyWith(
      content: content,
      status: MessageStatus.delivered,
    );
    await db.update(
      'messages',
      {
        'status': MessageStatus.delivered.index,
        if (content != existing.content) 'content': content,
      },
      where: 'id = ?',
      whereArgs: [message.id],
    );
    _messageController.add(message);
  }

  String _contentWithLocalPath(String content, String? localPath) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        final updated = Map<String, dynamic>.from(decoded);
        if (localPath != null && localPath.isNotEmpty) {
          updated['localPath'] = localPath;
        }
        updated.remove('retrying');
        if (mapEquals(decoded, updated)) return content;
        return jsonEncode(updated);
      }
    } catch (_) {
      // Legacy non-JSON media messages cannot safely carry structured paths.
    }
    return content;
  }

  /// Mark an outgoing file/media message failed when FileProvider reports error.
  Future<void> handleFileTransferFailed(String fileId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'messages',
      where: 'is_outgoing = 1 AND content LIKE ?',
      whereArgs: ['%$fileId%'],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final message =
        Message.fromMap(rows.first).copyWith(status: MessageStatus.failed);
    await db.update(
      'messages',
      {'status': MessageStatus.failed.index},
      where: 'id = ?',
      whereArgs: [message.id],
    );
    _messageController.add(message);
  }

  /// Mark messages as read
  Future<void> markAsRead(
    String conversationId, {
    ReadReceiptSender? readReceiptSender,
  }) async {
    _readReceiptSender = readReceiptSender ?? _readReceiptSender;
    final db = await DatabaseService.instance.database;

    final convRows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    final conversation =
        convRows.isNotEmpty ? Conversation.fromMap(convRows.first) : null;

    final unreadInboundRows = await db.query(
      'messages',
      columns: ['id'],
      where: 'conversation_id = ? AND is_outgoing = 0 AND status < ?',
      whereArgs: [conversationId, MessageStatus.read.index],
    );

    await db.update(
      'messages',
      {'status': MessageStatus.read.index},
      where: 'conversation_id = ? AND is_outgoing = 0 AND status < ?',
      whereArgs: [conversationId, MessageStatus.read.index],
    );

    await db.update(
      'conversations',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    if (readReceiptSender != null && conversation?.peerId != null) {
      for (final row in unreadInboundRows) {
        final messageId = row['id'] as String;
        final nativeMsgId = _localIdToNativeMsgId[messageId];
        if (nativeMsgId == null) continue;
        await _sendOrQueueReadReceipt(
          sender: readReceiptSender,
          toPeerId: conversation!.peerId!,
          msgId: nativeMsgId,
        );
      }
    }
  }

  /// Delete message
  Future<void> deleteMessage(
    String messageId, {
    MediaCleanup? mediaCleanup,
  }) async {
    final db = await DatabaseService.instance.database;

    // Get message info to find peer
    final msgRows =
        await db.query('messages', where: 'id = ?', whereArgs: [messageId]);
    if (msgRows.isEmpty) return;
    final msg = Message.fromMap(msgRows.first);

    // Get conversation to find peer ID
    final convRows = await db.query('conversations',
        where: 'id = ?', whereArgs: [msg.conversationId]);
    if (convRows.isEmpty) return;
    final conv = Conversation.fromMap(convRows.first);

    await _cleanupMessageMedia(msg, mediaCleanup: mediaCleanup);

    await db.update(
      'messages',
      {
        'is_deleted': 1,
        'content': '',
        'media_metadata': null,
        'thumbnail_path': null,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    await _emitMessageById(messageId);

    // Send delete notification via native chat
    if (_chatProvider != null && conv.peerId != null) {
      final nativeMsgId = _localIdToNativeMsgId[messageId];
      if (nativeMsgId != null) {
        await _chatProvider!.sendDelete(
          toPeerId: conv.peerId!,
          msgId: nativeMsgId,
        );
      }
    }
  }

  /// Edit message
  Future<void> editMessage(String messageId, String newContent) async {
    final db = await DatabaseService.instance.database;

    // Get message info to find peer
    final msgRows =
        await db.query('messages', where: 'id = ?', whereArgs: [messageId]);
    if (msgRows.isEmpty) return;
    final msg = Message.fromMap(msgRows.first);

    // Get conversation to find peer ID
    final convRows = await db.query('conversations',
        where: 'id = ?', whereArgs: [msg.conversationId]);
    if (convRows.isEmpty) return;
    final conv = Conversation.fromMap(convRows.first);

    await db.update(
      'messages',
      {'content': newContent, 'is_edited': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    await _emitMessageById(messageId);

    // Send edit via native chat
    if (_chatProvider != null && conv.peerId != null) {
      final nativeMsgId = _localIdToNativeMsgId[messageId];
      if (nativeMsgId != null) {
        await _chatProvider!.sendEdit(
          toPeerId: conv.peerId!,
          msgId: nativeMsgId,
          newText: newContent,
        );
      }
    }
  }

  /// Pin/unpin conversation
  Future<void> togglePin(String conversationId) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'conversations',
      columns: ['is_pinned'],
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    if (rows.isEmpty) return;

    final isPinned = (rows.first['is_pinned'] as int?) == 1;
    await db.update(
      'conversations',
      {'is_pinned': isPinned ? 0 : 1},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Mute/unmute conversation
  Future<void> toggleMute(String conversationId) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'conversations',
      columns: ['is_muted'],
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    if (rows.isEmpty) return;

    final isMuted = (rows.first['is_muted'] as int?) == 1;
    await db.update(
      'conversations',
      {'is_muted': isMuted ? 0 : 1},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Delete conversation and all its messages
  Future<void> deleteConversation(
    String conversationId, {
    MediaCleanup? mediaCleanup,
  }) async {
    final db = await DatabaseService.instance.database;

    final messageRows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    for (final row in messageRows) {
      await _cleanupMessageMedia(
        Message.fromMap(row),
        mediaCleanup: mediaCleanup,
      );
    }

    // Delete all messages in the conversation
    await db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    // Delete the conversation
    await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    debugPrint('ChatService: Deleted conversation $conversationId');
  }

  /// Update conversation display name (alias)
  Future<void> updateConversationDisplayName(
      String conversationId, String displayName) async {
    final db = await DatabaseService.instance.database;

    await db.update(
      'conversations',
      {'display_name': displayName},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  // ============================================================
  // Incoming Message Handlers
  // ============================================================

  /// Handle incoming text message from native layer
  Future<void> _handleIncomingMessage(ReceivedMessage received) async {
    final parsed = received.parseTextMessage();
    if (parsed == null) {
      debugPrint('ChatService: Failed to parse text message');
      return;
    }

    // Filter out messages from blocked contacts
    final isBlocked =
        await DatabaseService.instance.isContactBlocked(received.fromNodeId);
    if (isBlocked) {
      debugPrint(
          'ChatService: Message from blocked contact ${received.fromNodeId} ignored');
      return;
    }

    try {
      final db = await DatabaseService.instance.database;

      // Get or create conversation with sender
      final conversation =
          await getOrCreateDirectConversation(received.fromNodeId);

      // Create message
      final message = Message(
        id: _uuid.v4(),
        conversationId: conversation.id,
        senderId: received.fromNodeId,
        content: parsed.text,
        timestamp: received.receivedAt,
        status: MessageStatus.delivered,
        replyToId: parsed.replyToMsgId != null
            ? _nativeMsgIdToLocalId[parsed.replyToMsgId]
            : null,
        isOutgoing: false,
      );

      // Get disappearing messages setting for this conversation
      final disappearingSeconds = await DatabaseService.instance
              .getConversationDisappearingTimer(conversation.id) ??
          _defaultDisappearingSeconds;

      // Calculate disappears_at if disappearing is enabled
      int? disappearsAt;
      if (disappearingSeconds != null && disappearingSeconds > 0) {
        disappearsAt = DateTime.now().millisecondsSinceEpoch +
            (disappearingSeconds * 1000);
      }

      // Save to database (transaction ensures atomicity)
      final messageMap = message.toMap();
      messageMap['native_msg_id'] = received.msgId;
      if (disappearsAt != null) {
        messageMap['disappears_at'] = disappearsAt;
      }

      await db.transaction((txn) async {
        await txn.insert('messages', messageMap);
        await txn.update(
          'conversations',
          {
            'last_activity_at': message.timestamp.millisecondsSinceEpoch,
            'unread_count': conversation.unreadCount + 1,
          },
          where: 'id = ?',
          whereArgs: [conversation.id],
        );
      });

      _nativeMsgIdToLocalId[received.msgId] = message.id;
      _localIdToNativeMsgId[message.id] = received.msgId;

      // Emit to stream
      _messageController.add(message);

      // Show notification for incoming message
      await _showMessageNotification(
        conversationId: conversation.id,
        senderNodeId: received.fromNodeId,
        messageContent: parsed.text,
      );

      // Update sender's presence to online (they're actively messaging)
      await _updateSenderPresence(received.fromNodeId);

      // Send ACK back to sender
      if (_chatProvider != null) {
        debugPrint(
            'ChatService: Received message from ${received.fromNodeId}: ${parsed.text}');
      }
    } catch (e) {
      debugPrint('ChatService: Error handling incoming message: $e');
    }
  }

  /// Update sender's presence when we receive a message from them
  Future<void> _updateSenderPresence(String nodeId) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'contacts',
      {
        'presence': PresenceStatus.online.index,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
  }

  /// Show notification for incoming message
  Future<void> _showMessageNotification({
    required String conversationId,
    required String senderNodeId,
    required String messageContent,
  }) async {
    try {
      // Get sender display name from contacts
      final db = await DatabaseService.instance.database;
      final contacts = await db.query(
        'contacts',
        columns: ['display_name'],
        where: 'node_id = ?',
        whereArgs: [senderNodeId],
        limit: 1,
      );

      String senderName;
      if (contacts.isNotEmpty && contacts.first['display_name'] != null) {
        senderName = contacts.first['display_name'] as String;
      } else {
        // Fallback to short node ID
        senderName = senderNodeId.length > 12
            ? '${senderNodeId.substring(0, 12)}...'
            : senderNodeId;
      }

      // Show notification
      await NotificationService.instance.showMessageNotification(
        conversationId: conversationId,
        senderName: senderName,
        messageContent: messageContent,
      );
    } catch (e) {
      debugPrint('ChatService: Failed to show notification: $e');
    }
  }

  /// Handle ACK (delivery/read receipt)
  Future<void> _handleAck(AckData ack) async {
    final localId = _nativeMsgIdToLocalId[ack.msgId];
    if (localId == null) {
      debugPrint('ChatService: Unknown message ACK: ${ack.msgId}');
      return;
    }

    final db = await DatabaseService.instance.database;
    final newStatus = ack.isRead ? MessageStatus.read : MessageStatus.delivered;

    await db.update(
      'messages',
      {'status': newStatus.index},
      where: 'id = ?',
      whereArgs: [localId],
    );
    await _emitMessageById(localId);

    debugPrint('ChatService: Message $localId status: ${newStatus.name}');
  }

  /// Handle typing indicator
  void _handleTyping(TypingStatus status) {
    debugPrint(
        'ChatService: ${status.peerId} is ${status.isTyping ? "typing" : "not typing"}');
    // Typing status is managed by ChatProvider
    // UI can listen to chatProvider.typingStatuses
  }

  /// Handle reaction
  Future<void> _handleReaction(ReactionData reaction) async {
    final localId = _nativeMsgIdToLocalId[reaction.msgId];
    if (localId == null) {
      debugPrint('ChatService: Unknown message reaction: ${reaction.msgId}');
      return;
    }

    final db = await DatabaseService.instance.database;

    // Get current reactions
    final rows =
        await db.query('messages', where: 'id = ?', whereArgs: [localId]);
    if (rows.isEmpty) return;

    // For now, just log - proper reaction storage would need a separate table
    debugPrint(
        'ChatService: Reaction ${reaction.reaction} ${reaction.remove ? "removed from" : "added to"} $localId');
  }

  /// Handle delete request
  Future<void> _handleDelete(String nativeMsgId) async {
    final localId = _nativeMsgIdToLocalId[nativeMsgId];
    if (localId == null) {
      debugPrint('ChatService: Unknown message delete: $nativeMsgId');
      return;
    }

    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    await _cleanupMessageMedia(Message.fromMap(rows.first));

    await db.update(
      'messages',
      {
        'is_deleted': 1,
        'content': '',
        'media_metadata': null,
        'thumbnail_path': null,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
    await _emitMessageById(localId);

    debugPrint('ChatService: Message $localId deleted by sender');
  }

  /// Handle edit request
  Future<void> _handleEdit(EditData edit) async {
    final localId = _nativeMsgIdToLocalId[edit.msgId];
    if (localId == null) {
      debugPrint('ChatService: Unknown message edit: ${edit.msgId}');
      return;
    }

    final db = await DatabaseService.instance.database;

    await db.update(
      'messages',
      {'content': edit.newText, 'is_edited': 1},
      where: 'id = ?',
      whereArgs: [localId],
    );
    await _emitMessageById(localId);

    debugPrint('ChatService: Message $localId edited to: ${edit.newText}');
  }

  /// Retry sending a failed message
  Future<bool> retryMessage(
    String messageId,
    String conversationId, {
    MediaRetrySender? mediaRetrySender,
  }) async {
    final db = await DatabaseService.instance.database;

    // Load the message
    final rows = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
    if (rows.isEmpty) {
      debugPrint('ChatService: Message not found for retry: $messageId');
      return false;
    }

    final message = Message.fromMap(rows.first);

    // Only retry failed or pending messages
    if (message.status != MessageStatus.failed &&
        message.status != MessageStatus.pending) {
      debugPrint(
          'ChatService: Message status is ${message.status}, not retrying');
      return false;
    }

    // Get conversation for peer ID
    final convRows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    if (convRows.isEmpty) {
      debugPrint('ChatService: Conversation not found for retry');
      return false;
    }
    final conversation = Conversation.fromMap(convRows.first);

    if (conversation.peerId == null) {
      debugPrint('ChatService: No peer ID for conversation');
      return false;
    }

    // Update status to sending
    await db.update(
      'messages',
      {'status': MessageStatus.sending.index},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    if (message.type == MessageType.text) {
      if (_chatProvider == null) {
        debugPrint('ChatService: No chat provider for retry');
        await db.update(
          'messages',
          {'status': MessageStatus.failed.index},
          where: 'id = ?',
          whereArgs: [messageId],
        );
        return false;
      }

      // Look up previous native msg_id to reuse on retry (prevents duplicates)
      final previousNativeMsgId = _localIdToNativeMsgId[messageId];
      if (previousNativeMsgId != null) {
        debugPrint('ChatService: Retry with same msg_id: $previousNativeMsgId');
      }

      final result = await _chatProvider!.sendText(
        toPeerId: conversation.peerId!,
        text: message.content,
        replyToMsgId: null, // Don't preserve reply on retry
        localMsgId: messageId, // Track for ACK timeout
        nativeMsgIdHex: previousNativeMsgId, // Reuse original msg_id for dedup
      );

      if (result.success && result.nativeMsgId != null) {
        // Store mapping
        _nativeMsgIdToLocalId[result.nativeMsgId!] = messageId;
        _localIdToNativeMsgId[messageId] = result.nativeMsgId!;

        await db.update(
          'messages',
          {
            'status': MessageStatus.sent.index,
            'native_msg_id': result.nativeMsgId!,
          },
          where: 'id = ?',
          whereArgs: [messageId],
        );

        // Remove from offline queue if present
        await QueueService.instance.dequeue(messageId);

        debugPrint('ChatService: Retry successful for message $messageId');
        return true;
      } else {
        await db.update(
          'messages',
          {'status': MessageStatus.failed.index},
          where: 'id = ?',
          whereArgs: [messageId],
        );
        debugPrint('ChatService: Retry failed: ${result.error}');
        return false;
      }
    } else if (message.type == MessageType.file ||
        message.type == MessageType.audio ||
        message.type == MessageType.voice) {
      return _retryMediaMessage(
        db: db,
        message: message,
        conversation: conversation,
        mediaRetrySender: mediaRetrySender,
      );
    } else {
      debugPrint('ChatService: Cannot retry message type: ${message.type}');
      await db.update(
        'messages',
        {'status': MessageStatus.failed.index},
        where: 'id = ?',
        whereArgs: [messageId],
      );
      return false;
    }
  }

  Future<bool> _retryMediaMessage({
    required Database db,
    required Message message,
    required Conversation conversation,
    required MediaRetrySender? mediaRetrySender,
  }) async {
    if (mediaRetrySender == null) {
      debugPrint('ChatService: No media retry sender available');
      await db.update(
        'messages',
        {'status': MessageStatus.failed.index},
        where: 'id = ?',
        whereArgs: [message.id],
      );
      return false;
    }

    final metadata = _decodeMessageContent(message.content);
    final fileId = metadata?['fileId'] as String?;
    final filename = metadata?['filename'] as String?;
    final localPath = metadata?['localPath'] as String?;
    if (metadata == null || fileId == null || filename == null) {
      debugPrint('ChatService: Media retry missing file metadata');
      await db.update(
        'messages',
        {'status': MessageStatus.failed.index},
        where: 'id = ?',
        whereArgs: [message.id],
      );
      return false;
    }

    final result = await mediaRetrySender(
      toPeerId: conversation.peerId!,
      fileId: fileId,
      filename: filename,
      messageType: message.type,
      localPath: localPath,
    );

    if (!result.success || result.fileId == null) {
      debugPrint('ChatService: Media retry failed: ${result.error}');
      await db.update(
        'messages',
        {'status': MessageStatus.failed.index},
        where: 'id = ?',
        whereArgs: [message.id],
      );
      return false;
    }

    final updatedMetadata = Map<String, dynamic>.from(metadata)
      ..['fileId'] = result.fileId!
      ..['retrying'] = true;
    if (result.localPath != null) {
      updatedMetadata['localPath'] = result.localPath!;
    }
    final updatedContent = jsonEncode(updatedMetadata);
    final updatedMessage = message.copyWith(
      content: updatedContent,
      status: MessageStatus.sending,
    );

    await db.update(
      'messages',
      {
        'content': updatedContent,
        'status': MessageStatus.sending.index,
      },
      where: 'id = ?',
      whereArgs: [message.id],
    );
    _messageController.add(updatedMessage);
    debugPrint('ChatService: Media retry started for ${message.id}');
    return true;
  }

  Map<String, dynamic>? _decodeMessageContent(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _sendOrQueueReadReceipt({
    required ReadReceiptSender sender,
    required String toPeerId,
    required String msgId,
  }) async {
    try {
      final sent = await sender(toPeerId: toPeerId, msgId: msgId);
      if (sent) {
        _pendingReadReceipts.remove(_readReceiptKey(toPeerId, msgId));
        if (_pendingReadReceipts.isEmpty) _stopReadReceiptRetryTimer();
        return;
      }
    } catch (e) {
      debugPrint('ChatService: Read receipt send failed: $e');
    }

    _queueReadReceipt(toPeerId: toPeerId, msgId: msgId);
  }

  void _queueReadReceipt({
    required String toPeerId,
    required String msgId,
    int attempts = 1,
  }) {
    final key = _readReceiptKey(toPeerId, msgId);
    final existing = _pendingReadReceipts[key];
    if (existing != null) return;

    _pendingReadReceipts[key] = _PendingReadReceipt(
      toPeerId: toPeerId,
      msgId: msgId,
      attempts: attempts,
      nextAttemptAt: DateTime.now().add(_readReceiptBackoff(attempts)),
    );
    _startReadReceiptRetryTimer();
    debugPrint('ChatService: Queued read receipt retry for $msgId');
  }

  void _startReadReceiptRetryTimer() {
    _readReceiptRetryTimer ??= Timer.periodic(
      _readReceiptRetryInterval,
      (_) => unawaited(_flushReadReceiptRetries()),
    );
  }

  void _stopReadReceiptRetryTimer() {
    _readReceiptRetryTimer?.cancel();
    _readReceiptRetryTimer = null;
  }

  Future<void> _flushReadReceiptRetries() async {
    if (_flushingReadReceipts || _pendingReadReceipts.isEmpty) return;
    final sender = _readReceiptSender;
    if (sender == null) return;

    _flushingReadReceipts = true;
    try {
      final now = DateTime.now();
      final ready = _pendingReadReceipts.values
          .where((receipt) => !receipt.nextAttemptAt.isAfter(now))
          .toList();

      for (final receipt in ready) {
        final key = _readReceiptKey(receipt.toPeerId, receipt.msgId);
        try {
          final sent = await sender(
            toPeerId: receipt.toPeerId,
            msgId: receipt.msgId,
          );
          if (sent) {
            _pendingReadReceipts.remove(key);
            continue;
          }
        } catch (e) {
          debugPrint('ChatService: Read receipt retry failed: $e');
        }

        final attempts = receipt.attempts + 1;
        if (attempts > _readReceiptMaxAttempts) {
          _pendingReadReceipts.remove(key);
          debugPrint('ChatService: Dropped read receipt after retries');
          continue;
        }

        _pendingReadReceipts[key] = receipt.copyWith(
          attempts: attempts,
          nextAttemptAt: now.add(_readReceiptBackoff(attempts)),
        );
      }
    } finally {
      _flushingReadReceipts = false;
      if (_pendingReadReceipts.isEmpty) _stopReadReceiptRetryTimer();
    }
  }

  Duration _readReceiptBackoff(int attempts) {
    final seconds = _readReceiptBaseBackoff.inSeconds * (1 << (attempts - 1));
    if (seconds >= _readReceiptMaxBackoff.inSeconds) {
      return _readReceiptMaxBackoff;
    }
    return Duration(seconds: seconds);
  }

  String _readReceiptKey(String toPeerId, String msgId) => '$toPeerId:$msgId';

  Future<void> _cleanupMessageMedia(
    Message message, {
    MediaCleanup? mediaCleanup,
  }) async {
    final refs = _storedMediaRefs(message);
    for (final ref in refs) {
      try {
        if (mediaCleanup != null) {
          await mediaCleanup(fileId: ref.fileId, localPath: ref.localPath);
        } else if (ref.localPath != null) {
          await FileProvider.deleteStoredMediaPath(ref.localPath!);
        }
      } catch (e) {
        debugPrint(
          'ChatService: Failed to delete stored media for ${message.id}: $e',
        );
      }
    }
  }

  List<_StoredMediaRef> _storedMediaRefs(Message message) {
    final refs = <_StoredMediaRef>[];
    final seen = <String>{};

    void addRef({String? fileId, String? localPath}) {
      if ((fileId == null || fileId.isEmpty) &&
          (localPath == null || localPath.isEmpty)) {
        return;
      }

      final key = '${fileId ?? ''}|${localPath ?? ''}';
      if (!seen.add(key)) return;
      refs.add(_StoredMediaRef(fileId: fileId, localPath: localPath));
    }

    void addRefsFromJson(String? value) {
      if (value == null || value.isEmpty) return;
      final decoded = _decodeMessageContent(value);
      if (decoded == null) return;
      final fileId = decoded['fileId'] as String?;
      addRef(fileId: fileId, localPath: decoded['localPath'] as String?);
      addRef(fileId: fileId, localPath: decoded['filePath'] as String?);
      addRef(fileId: null, localPath: decoded['thumbnailPath'] as String?);
    }

    addRefsFromJson(message.content);
    addRefsFromJson(message.mediaMetadata);
    addRef(fileId: null, localPath: message.thumbnailPath);

    return refs;
  }

  /// Update message status
  Future<void> updateMessageStatus(
      String messageId, MessageStatus status) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'messages',
      {'status': status.index},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Retry sending a message from the offline queue
  /// This is called by QueueProvider for automatic retries
  /// Returns true if send was successful
  Future<bool> retrySendFromQueue(
    String messageId,
    String recipientId,
    List<int> data,
  ) async {
    if (_chatProvider == null) {
      debugPrint('ChatService: No chat provider for queue retry');
      return false;
    }

    final db = await DatabaseService.instance.database;

    // Decode message content
    final content = utf8.decode(data, allowMalformed: true);

    // Update status to sending
    await db.update(
      'messages',
      {'status': MessageStatus.sending.index},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // Look up previous native msg_id to reuse on retry (prevents duplicates)
    final previousNativeMsgId = _localIdToNativeMsgId[messageId];
    if (previousNativeMsgId != null) {
      debugPrint(
          'ChatService: Queue retry with same msg_id: $previousNativeMsgId');
    }

    // Try to send via native chat
    final result = await _chatProvider!.sendText(
      toPeerId: recipientId,
      text: content,
      replyToMsgId: null, // Don't preserve reply on retry
      nativeMsgIdHex: previousNativeMsgId, // Reuse original msg_id for dedup
      // Don't track queue retries for ACK - already retrying
    );

    if (result.success && result.nativeMsgId != null) {
      // Store mapping
      _nativeMsgIdToLocalId[result.nativeMsgId!] = messageId;
      _localIdToNativeMsgId[messageId] = result.nativeMsgId!;

      // Update status to sent
      await db.update(
        'messages',
        {
          'status': MessageStatus.sent.index,
          'native_msg_id': result.nativeMsgId!,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );

      // Remove from queue
      await QueueService.instance.dequeue(messageId);

      debugPrint('ChatService: Queue retry successful for message $messageId');
      return true;
    } else {
      // Keep as failed - QueueProvider will handle retry scheduling
      await db.update(
        'messages',
        {'status': MessageStatus.failed.index},
        where: 'id = ?',
        whereArgs: [messageId],
      );
      debugPrint('ChatService: Queue retry failed: ${result.error}');
      return false;
    }
  }

  /// Parse size string (e.g., "12.5 KB", "1.2 MB") to bytes
  int _parseSizeToBytes(String sizeStr) {
    final match = RegExp(r'([\d.]+)\s*(\w+)').firstMatch(sizeStr);
    if (match == null) return 0;

    final value = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = match.group(2)?.toUpperCase() ?? 'B';

    switch (unit) {
      case 'B':
        return value.round();
      case 'KB':
        return (value * 1024).round();
      case 'MB':
        return (value * 1024 * 1024).round();
      case 'GB':
        return (value * 1024 * 1024 * 1024).round();
      default:
        return value.round();
    }
  }

  /// Normalize peer ID from 64-char hex (with trailing zeros) to UUID format
  String _normalizePeerId(String peerId) {
    // If already UUID format, return as-is
    if (NodeIdUtils.isUuidFormat(peerId)) {
      return peerId;
    }

    // Check if it's 64-char hex with trailing zeros (UUID stored in 32 bytes)
    if (peerId.length == 64) {
      // Check if bytes 17-32 (chars 32-63) are all zeros
      final trailingPart = peerId.substring(32);
      if (trailingPart == '0' * 32) {
        // Convert first 32 chars (16 bytes) to UUID format
        final hexPart = peerId.substring(0, 32);
        return '${hexPart.substring(0, 8)}-${hexPart.substring(8, 12)}-${hexPart.substring(12, 16)}-${hexPart.substring(16, 20)}-${hexPart.substring(20, 32)}';
      }
    }

    // Return as-is if no conversion needed
    return peerId;
  }

  void dispose() {
    disconnectProvider();
    _disappearingMessagesTimer?.cancel();
    _disappearingMessagesTimer = null;
    _stopReadReceiptRetryTimer();
    _messageController.close();
  }

  @visibleForTesting
  void resetForTesting() {
    disconnectProvider();
    _disappearingMessagesTimer?.cancel();
    _disappearingMessagesTimer = null;
    _stopReadReceiptRetryTimer();
    _nativeMsgIdToLocalId.clear();
    _localIdToNativeMsgId.clear();
    _pendingReadReceipts.clear();
    _readReceiptSender = null;
    _flushingReadReceipts = false;
  }
}

class _StoredMediaRef {
  final String? fileId;
  final String? localPath;

  const _StoredMediaRef({
    required this.fileId,
    required this.localPath,
  });
}

class _PendingReadReceipt {
  final String toPeerId;
  final String msgId;
  final int attempts;
  final DateTime nextAttemptAt;

  const _PendingReadReceipt({
    required this.toPeerId,
    required this.msgId,
    required this.attempts,
    required this.nextAttemptAt,
  });

  _PendingReadReceipt copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
  }) {
    return _PendingReadReceipt(
      toPeerId: toPeerId,
      msgId: msgId,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    );
  }
}
