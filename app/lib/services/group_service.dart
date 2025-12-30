import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'database_service.dart';
import 'identity_service.dart';

/// Service for group chat operations
class GroupService {
  static final GroupService instance = GroupService._();

  final _uuid = const Uuid();
  final _messageController = StreamController<Message>.broadcast();
  final _groupUpdateController = StreamController<Group>.broadcast();

  GroupService._();

  /// Stream of new group messages
  Stream<Message> get messageStream => _messageController.stream;

  /// Stream of group updates (member changes, etc)
  Stream<Group> get groupUpdateStream => _groupUpdateController.stream;

  /// Get all groups
  Future<List<Group>> getGroups() async {
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery('''
      SELECT g.*,
        (SELECT content FROM messages
         WHERE conversation_id = g.id
         ORDER BY timestamp DESC LIMIT 1) as last_message_text,
        (SELECT timestamp FROM messages
         WHERE conversation_id = g.id
         ORDER BY timestamp DESC LIMIT 1) as last_message_at,
        (SELECT COUNT(*) FROM messages
         WHERE conversation_id = g.id AND is_outgoing = 0 AND status < 4) as unread_count
      FROM groups g
      ORDER BY g.updated_at DESC
    ''');

    final groups = <Group>[];
    for (final row in rows) {
      final group = Group.fromMap(row);
      // Load members
      final members = await getGroupMembers(group.id);
      groups.add(group.copyWith(members: members));
    }
    return groups;
  }

  /// Get group by ID
  Future<Group?> getGroup(String id) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (rows.isEmpty) return null;

    final group = Group.fromMap(rows.first);
    final members = await getGroupMembers(id);
    return group.copyWith(members: members);
  }

  /// Get group members
  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'role DESC, joined_at ASC',
    );

    return rows.map((row) => GroupMember.fromMap(row)).toList();
  }

  /// Create new group
  Future<Group> createGroup(String name, {String? description}) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      throw StateError('No identity');
    }

    final id = _uuid.v4();
    final now = DateTime.now();

    final group = Group(
      id: id,
      name: name,
      description: description,
      creatorId: identity.nodeId,
      keyVersion: 1,
      createdAt: now,
      updatedAt: now,
    );

    // Save group
    await db.insert('groups', group.toMap());

    // Add ourselves as owner
    final selfMember = GroupMember(
      groupId: id,
      nodeId: identity.nodeId,
      role: GroupRole.owner,
      displayName: identity.displayName,
      joinedAt: now,
    );
    await db.insert('group_members', selfMember.toMap());

    // Create corresponding conversation entry for unified inbox
    await db.insert('conversations', {
      'id': id,
      'type': 1, // ConversationType.group
      'group_id': id,
      'title': name,
      'is_pinned': 0,
      'is_muted': 0,
      'is_archived': 0,
      'unread_count': 0,
      'last_activity_at': now.millisecondsSinceEpoch,
    });

    final result = group.copyWith(members: [selfMember]);
    _groupUpdateController.add(result);
    return result;
  }

  /// Invite contact to group
  Future<void> inviteMember(String groupId, String nodeId) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();

    // Check if already member
    final existing = await db.query(
      'group_members',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, nodeId],
    );
    if (existing.isNotEmpty) return;

    // Get contact info for display name
    final contacts = await db.query(
      'contacts',
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
    final displayName = contacts.isNotEmpty
        ? contacts.first['display_name'] as String?
        : null;

    final member = GroupMember(
      groupId: groupId,
      nodeId: nodeId,
      role: GroupRole.member,
      displayName: displayName,
      joinedAt: now,
    );

    await db.insert('group_members', member.toMap());

    // Update group timestamp
    await db.update(
      'groups',
      {'updated_at': now.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    // TODO: Send invite via libcyxchat FFI
  }

  /// Remove member from group
  Future<void> removeMember(String groupId, String nodeId) async {
    final db = await DatabaseService.instance.database;

    await db.delete(
      'group_members',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, nodeId],
    );

    // Update group timestamp
    await db.update(
      'groups',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    // TODO: Send kick notification via libcyxchat FFI
  }

  /// Leave group
  Future<void> leaveGroup(String groupId) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return;

    // Remove self from members
    await db.delete(
      'group_members',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, identity.nodeId],
    );

    // Remove from conversations
    await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // TODO: Send leave notification via libcyxchat FFI
  }

  /// Promote member to admin
  Future<void> promoteAdmin(String groupId, String nodeId) async {
    final db = await DatabaseService.instance.database;

    await db.update(
      'group_members',
      {'role': GroupRole.admin.index},
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, nodeId],
    );

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    // TODO: Broadcast admin change via libcyxchat FFI
  }

  /// Demote admin to member
  Future<void> demoteAdmin(String groupId, String nodeId) async {
    final db = await DatabaseService.instance.database;

    await db.update(
      'group_members',
      {'role': GroupRole.member.index},
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, nodeId],
    );

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    // TODO: Broadcast admin change via libcyxchat FFI
  }

  /// Update group name
  Future<void> updateName(String groupId, String name) async {
    final db = await DatabaseService.instance.database;

    await db.update(
      'groups',
      {
        'name': name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Update conversation title
    await db.update(
      'conversations',
      {'title': name},
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }
  }

  /// Update group description
  Future<void> updateDescription(String groupId, String? description) async {
    final db = await DatabaseService.instance.database;

    await db.update(
      'groups',
      {
        'description': description,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }
  }

  /// Send message to group
  Future<Message> sendMessage(
    String groupId,
    String content, {
    String? replyToId,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      throw StateError('No identity');
    }

    final message = Message(
      id: _uuid.v4(),
      conversationId: groupId,
      senderId: identity.nodeId,
      content: content,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      replyToId: replyToId,
      isOutgoing: true,
    );

    // Save to database
    await db.insert('messages', message.toMap());

    // Update conversation timestamp
    await db.update(
      'conversations',
      {'last_activity_at': message.timestamp.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Update group timestamp
    await db.update(
      'groups',
      {'updated_at': message.timestamp.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // TODO: Send via libcyxchat FFI
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

  /// Get messages for group
  Future<List<Message>> getMessages(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map((row) => Message.fromMap(row)).toList().reversed.toList();
  }

  /// Mark group messages as read
  Future<void> markAsRead(String groupId) async {
    final db = await DatabaseService.instance.database;

    await db.update(
      'messages',
      {'status': MessageStatus.read.index},
      where: 'conversation_id = ? AND is_outgoing = 0 AND status < ?',
      whereArgs: [groupId, MessageStatus.read.index],
    );

    await db.update(
      'conversations',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  void dispose() {
    _messageController.close();
    _groupUpdateController.close();
  }
}
