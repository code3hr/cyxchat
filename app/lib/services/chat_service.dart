import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'database_service.dart';
import 'identity_service.dart';

/// Service for chat operations
class ChatService {
  static final ChatService instance = ChatService._();

  final _uuid = const Uuid();
  final _messageController = StreamController<Message>.broadcast();

  ChatService._();

  /// Stream of new messages
  Stream<Message> get messageStream => _messageController.stream;

  /// Get all conversations
  Future<List<Conversation>> getConversations() async {
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery('''
      SELECT c.*, m.* as last_message
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

    // TODO: Send via libcyxchat
    // For now, mark as sent
    final sentMessage = message.copyWith(status: MessageStatus.sent);
    await db.update(
      'messages',
      {'status': MessageStatus.sent.index},
      where: 'id = ?',
      whereArgs: [message.id],
    );

    _messageController.add(sentMessage);
    return sentMessage;
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

    await db.update(
      'messages',
      {'is_deleted': 1, 'content': ''},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // TODO: Send delete notification via libcyxchat
  }

  /// Edit message
  Future<void> editMessage(String messageId, String newContent) async {
    final db = await DatabaseService.instance.database;

    await db.update(
      'messages',
      {'content': newContent, 'is_edited': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // TODO: Send edit via libcyxchat
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

  void dispose() {
    _messageController.close();
  }
}
