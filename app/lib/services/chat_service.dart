import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../providers/chat_provider.dart';
import 'database_service.dart';
import 'identity_service.dart';

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

  ChatService._();

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
    _messageSubscription = provider.messageStream.listen(_handleIncomingMessage);
    _ackSubscription = provider.ackStream.listen(_handleAck);
    _typingSubscription = provider.typingStream.listen(_handleTyping);
    _reactionSubscription = provider.reactionStream.listen(_handleReaction);
    _deleteSubscription = provider.deleteStream.listen(_handleDelete);
    _editSubscription = provider.editStream.listen(_handleEdit);

    debugPrint('ChatService: Connected to ChatProvider');
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
      return Conversation.fromMap(existing.first);
    }

    // Create new
    final id = _uuid.v4();
    final conversation = Conversation(
      id: id,
      type: ConversationType.direct,
      peerId: peerId,
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

  /// Send text message
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String? replyToId,
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
      content: content,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      replyToId: replyToId,
      isOutgoing: true,
    );

    // Save to database
    await db.insert('messages', message.toMap());

    // Update conversation
    await db.update(
      'conversations',
      {
        'last_activity_at': message.timestamp.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    // Try to send via native chat
    Message resultMessage;
    if (_chatProvider != null && conversation.peerId != null) {
      // Get native reply-to ID if replying
      String? nativeReplyToId;
      if (replyToId != null) {
        nativeReplyToId = _localIdToNativeMsgId[replyToId];
      }

      final result = await _chatProvider!.sendText(
        toPeerId: conversation.peerId!,
        text: content,
        replyToMsgId: nativeReplyToId,
      );

      if (result.success && result.nativeMsgId != null) {
        // Store mapping
        _nativeMsgIdToLocalId[result.nativeMsgId!] = message.id;
        _localIdToNativeMsgId[message.id] = result.nativeMsgId!;

        resultMessage = message.copyWith(status: MessageStatus.sent);
        await db.update(
          'messages',
          {'status': MessageStatus.sent.index},
          where: 'id = ?',
          whereArgs: [message.id],
        );
      } else {
        // Send failed - mark as failed
        resultMessage = message.copyWith(status: MessageStatus.failed);
        await db.update(
          'messages',
          {'status': MessageStatus.failed.index},
          where: 'id = ?',
          whereArgs: [message.id],
        );
        debugPrint('ChatService: Send failed: ${result.error}');
      }
    } else {
      // No native chat available - mark as pending
      resultMessage = message.copyWith(status: MessageStatus.pending);
      await db.update(
        'messages',
        {'status': MessageStatus.pending.index},
        where: 'id = ?',
        whereArgs: [message.id],
      );
      debugPrint('ChatService: No native chat available, message queued');
    }

    _messageController.add(resultMessage);
    return resultMessage;
  }

  /// Mark messages as read
  Future<void> markAsRead(String conversationId) async {
    final db = await DatabaseService.instance.database;

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
  }

  /// Delete message
  Future<void> deleteMessage(String messageId) async {
    final db = await DatabaseService.instance.database;

    // Get message info to find peer
    final msgRows = await db.query('messages', where: 'id = ?', whereArgs: [messageId]);
    if (msgRows.isEmpty) return;
    final msg = Message.fromMap(msgRows.first);

    // Get conversation to find peer ID
    final convRows = await db.query('conversations', where: 'id = ?', whereArgs: [msg.conversationId]);
    if (convRows.isEmpty) return;
    final conv = Conversation.fromMap(convRows.first);

    await db.update(
      'messages',
      {'is_deleted': 1, 'content': ''},
      where: 'id = ?',
      whereArgs: [messageId],
    );

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
    final msgRows = await db.query('messages', where: 'id = ?', whereArgs: [messageId]);
    if (msgRows.isEmpty) return;
    final msg = Message.fromMap(msgRows.first);

    // Get conversation to find peer ID
    final convRows = await db.query('conversations', where: 'id = ?', whereArgs: [msg.conversationId]);
    if (convRows.isEmpty) return;
    final conv = Conversation.fromMap(convRows.first);

    await db.update(
      'messages',
      {'content': newContent, 'is_edited': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );

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

    final db = await DatabaseService.instance.database;

    // Get or create conversation with sender
    final conversation = await getOrCreateDirectConversation(received.fromNodeId);

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

    // Save to database
    await db.insert('messages', message.toMap());

    // Update conversation
    await db.update(
      'conversations',
      {
        'last_activity_at': message.timestamp.millisecondsSinceEpoch,
        'unread_count': conversation.unreadCount + 1,
      },
      where: 'id = ?',
      whereArgs: [conversation.id],
    );

    // Emit to stream
    _messageController.add(message);

    // Update sender's presence to online (they're actively messaging)
    await _updateSenderPresence(received.fromNodeId);

    // Send ACK back to sender
    if (_chatProvider != null) {
      // Need native msg ID to ACK - but we don't have it from the wire format
      // The native layer should handle ACK automatically via callback
      debugPrint('ChatService: Received message from ${received.fromNodeId}: ${parsed.text}');
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

    debugPrint('ChatService: Message $localId status: ${newStatus.name}');
  }

  /// Handle typing indicator
  void _handleTyping(TypingStatus status) {
    debugPrint('ChatService: ${status.peerId} is ${status.isTyping ? "typing" : "not typing"}');
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
    final rows = await db.query('messages', where: 'id = ?', whereArgs: [localId]);
    if (rows.isEmpty) return;

    // For now, just log - proper reaction storage would need a separate table
    debugPrint('ChatService: Reaction ${reaction.reaction} ${reaction.remove ? "removed from" : "added to"} $localId');
  }

  /// Handle delete request
  Future<void> _handleDelete(String nativeMsgId) async {
    final localId = _nativeMsgIdToLocalId[nativeMsgId];
    if (localId == null) {
      debugPrint('ChatService: Unknown message delete: $nativeMsgId');
      return;
    }

    final db = await DatabaseService.instance.database;

    await db.update(
      'messages',
      {'is_deleted': 1, 'content': ''},
      where: 'id = ?',
      whereArgs: [localId],
    );

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

    debugPrint('ChatService: Message $localId edited to: ${edit.newText}');
  }

  void dispose() {
    disconnectProvider();
    _messageController.close();
  }
}
