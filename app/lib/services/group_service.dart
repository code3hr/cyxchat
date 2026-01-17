import 'dart:async';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Sqflite;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../providers/group_ffi_provider.dart';
import 'database_service.dart';
import 'identity_service.dart';
import 'log_service.dart';

/// Service for group chat operations
/// Combines database persistence with FFI network operations
class GroupService {
  static final GroupService instance = GroupService._();

  final _uuid = const Uuid();
  final _messageController = StreamController<Message>.broadcast();
  final _groupUpdateController = StreamController<Group>.broadcast();
  final _log = LogService.instance;

  GroupFFIProvider? _ffiProvider;
  final List<StreamSubscription> _subscriptions = [];

  GroupService._();

  /// Stream of new group messages
  Stream<Message> get messageStream => _messageController.stream;

  /// Stream of group updates (member changes, etc)
  Stream<Group> get groupUpdateStream => _groupUpdateController.stream;

  /// Connect to the FFI provider for network operations
  void connectProvider(GroupFFIProvider provider) {
    if (_ffiProvider != null) {
      _log.warning('GroupService already connected to FFI provider',
          source: 'GroupService');
      return;
    }

    _ffiProvider = provider;
    _setupStreamSubscriptions();
    _log.info('Connected to GroupFFIProvider', source: 'GroupService');
  }

  /// Disconnect from FFI provider
  void disconnectProvider() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _ffiProvider = null;
    _log.info('Disconnected from GroupFFIProvider', source: 'GroupService');
  }

  /// Set up subscriptions to FFI streams
  void _setupStreamSubscriptions() {
    final provider = _ffiProvider;
    if (provider == null) return;

    // Subscribe to incoming messages
    _subscriptions.add(
      provider.messageStream.listen(_handleIncomingMessage),
    );

    // Subscribe to member events (join/leave)
    _subscriptions.add(
      provider.memberEventStream.listen(_handleMemberEvent),
    );

    // Subscribe to key update events
    _subscriptions.add(
      provider.keyUpdateStream.listen(_handleKeyUpdate),
    );

    // Subscribe to group invites
    _subscriptions.add(
      provider.inviteStream.listen(_handleGroupInvite),
    );
  }

  /// Handle incoming group message from FFI
  Future<void> _handleIncomingMessage(GroupMessageReceived msg) async {
    _log.info(
        'Received group message from ${msg.fromNodeId.substring(0, 8)}...',
        source: 'GroupService');

    final db = await DatabaseService.instance.database;

    // Check if group exists in our database
    final groupRows = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [msg.groupId],
    );
    if (groupRows.isEmpty) {
      _log.warning('Received message for unknown group ${msg.groupId}',
          source: 'GroupService');
      return;
    }

    // Create message record
    final message = Message(
      id: msg.msgId,
      conversationId: msg.groupId,
      senderId: msg.fromNodeId,
      content: msg.text,
      timestamp: msg.receivedAt,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );

    // Save to database
    await db.insert('messages', message.toMap());

    // Update conversation timestamp and unread count
    await db.rawUpdate('''
      UPDATE conversations
      SET last_activity_at = ?,
          unread_count = unread_count + 1
      WHERE id = ?
    ''', [message.timestamp.millisecondsSinceEpoch, msg.groupId]);

    // Update group timestamp
    await db.update(
      'groups',
      {'updated_at': message.timestamp.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [msg.groupId],
    );

    _messageController.add(message);
  }

  /// Handle member event (join or leave) from FFI
  Future<void> _handleMemberEvent(MemberEvent event) async {
    if (event.isJoin) {
      await _handleMemberJoin(event);
    } else {
      await _handleMemberLeave(event);
    }
  }

  /// Handle member join
  Future<void> _handleMemberJoin(MemberEvent event) async {
    _log.info('Member ${event.memberId.substring(0, 8)}... joined group',
        source: 'GroupService');

    final db = await DatabaseService.instance.database;

    // Check if already member
    final existing = await db.query(
      'group_members',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [event.groupId, event.memberId],
    );
    if (existing.isNotEmpty) return;

    // Get contact info for display name
    final contacts = await db.query(
      'contacts',
      where: 'node_id = ?',
      whereArgs: [event.memberId],
    );
    final displayName = contacts.isNotEmpty
        ? contacts.first['display_name'] as String?
        : null;

    final member = GroupMember(
      groupId: event.groupId,
      nodeId: event.memberId,
      role: GroupRole.member,
      displayName: displayName,
      joinedAt: event.timestamp,
    );

    await db.insert('group_members', member.toMap());

    // Update group timestamp
    await db.update(
      'groups',
      {'updated_at': event.timestamp.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [event.groupId],
    );

    // Notify update
    final group = await getGroup(event.groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }
  }

  /// Handle member leave
  Future<void> _handleMemberLeave(MemberEvent event) async {
    _log.info(
        'Member ${event.memberId.substring(0, 8)}... left group (kicked: ${event.wasKicked})',
        source: 'GroupService');

    final db = await DatabaseService.instance.database;

    await db.delete(
      'group_members',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [event.groupId, event.memberId],
    );

    // Update group timestamp
    await db.update(
      'groups',
      {'updated_at': event.timestamp.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [event.groupId],
    );

    // Notify update
    final group = await getGroup(event.groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }
  }

  /// Handle key update event from FFI
  Future<void> _handleKeyUpdate(KeyUpdateEvent event) async {
    _log.info('Group key updated to version ${event.newVersion}',
        source: 'GroupService');

    final db = await DatabaseService.instance.database;

    await db.update(
      'groups',
      {
        'key_version': event.newVersion,
        'updated_at': event.timestamp.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [event.groupId],
    );

    // Notify update
    final group = await getGroup(event.groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }
  }

  /// Handle group invite from FFI
  Future<void> _handleGroupInvite(GroupInvite invite) async {
    _log.info('Received invite to group "${invite.groupName}"',
        source: 'GroupService');
    // Invites are managed by GroupFFIProvider.pendingInvites
    // UI can listen to that provider for invite list
  }

  // ============================================================
  // Public API - Database Queries
  // ============================================================

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

  // ============================================================
  // Public API - Group Operations (Database + FFI)
  // ============================================================

  /// Create new group
  Future<Group> createGroup(String name, {String? description}) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      throw StateError('No identity');
    }

    // Create group via FFI first (if connected)
    String groupId;
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = await _ffiProvider!.createGroup(name);
      if (!result.success || result.groupId == null) {
        throw StateError('Failed to create group via FFI: ${result.error}');
      }
      groupId = result.groupId!;
    } else {
      // Fallback to local-only group (for testing/offline)
      groupId = _uuid.v4();
      _log.warning('Creating local-only group (FFI not connected)',
          source: 'GroupService');
    }

    final now = DateTime.now();
    final group = Group(
      id: groupId,
      name: name,
      description: description,
      creatorId: identity.nodeId,
      keyVersion: 1,
      createdAt: now,
      updatedAt: now,
    );

    // Save group to database
    await db.insert('groups', group.toMap());

    // Add ourselves as owner
    final selfMember = GroupMember(
      groupId: groupId,
      nodeId: identity.nodeId,
      role: GroupRole.owner,
      displayName: identity.displayName,
      joinedAt: now,
    );
    await db.insert('group_members', selfMember.toMap());

    // Create corresponding conversation entry for unified inbox
    await db.insert('conversations', {
      'id': groupId,
      'type': 1, // ConversationType.group
      'group_id': groupId,
      'display_name': name,
      'is_pinned': 0,
      'is_muted': 0,
      'unread_count': 0,
      'last_activity_at': now.millisecondsSinceEpoch,
    });

    // Set description via FFI if provided
    if (description != null && _ffiProvider != null) {
      await _ffiProvider!.setGroupDescription(groupId, description);
    }

    final result = group.copyWith(members: [selfMember]);
    _groupUpdateController.add(result);
    return result;
  }

  /// Invite contact to group
  Future<bool> inviteMember(
    String groupId,
    String nodeId, {
    List<int>? memberPubkey,
  }) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();

    // Check if already member
    final existing = await db.query(
      'group_members',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, nodeId],
    );
    if (existing.isNotEmpty) {
      _log.warning('Member already in group', source: 'GroupService');
      return false;
    }

    // Get contact info for display name and pubkey
    final contacts = await db.query(
      'contacts',
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
    final displayName = contacts.isNotEmpty
        ? contacts.first['display_name'] as String?
        : null;

    // Get pubkey from contact if not provided
    List<int>? pubkey = memberPubkey;
    if (pubkey == null && contacts.isNotEmpty) {
      final pubkeyStr = contacts.first['public_key'] as String?;
      if (pubkeyStr != null) {
        pubkey = _hexToBytes(pubkeyStr);
      }
    }

    // Send invite via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      if (pubkey == null || pubkey.length != 32) {
        _log.error('Cannot invite: missing public key for member',
            source: 'GroupService');
        return false;
      }

      final success = await _ffiProvider!.inviteMember(
        groupId: groupId,
        memberId: nodeId,
        memberPubkey: pubkey,
      );
      if (!success) {
        return false;
      }
    }

    // Add to local database (they'll be marked as pending until they accept)
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

    return true;
  }

  /// Remove member from group (admin only)
  Future<bool> removeMember(String groupId, String nodeId) async {
    final db = await DatabaseService.instance.database;

    // Remove via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.removeMember(
        groupId: groupId,
        memberId: nodeId,
      );
      if (!success) {
        return false;
      }
    }

    // Remove from local database
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

    return true;
  }

  /// Leave group
  Future<bool> leaveGroup(String groupId) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return false;

    // Leave via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.leaveGroup(groupId);
      if (!success) {
        return false;
      }
    }

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

    // Remove the group itself
    await db.delete(
      'groups',
      where: 'id = ?',
      whereArgs: [groupId],
    );

    return true;
  }

  /// Promote member to admin (owner only)
  Future<bool> promoteAdmin(String groupId, String nodeId) async {
    final db = await DatabaseService.instance.database;

    // Promote via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.addAdmin(
        groupId: groupId,
        memberId: nodeId,
      );
      if (!success) {
        return false;
      }
    }

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

    return true;
  }

  /// Demote admin to member (owner only)
  Future<bool> demoteAdmin(String groupId, String nodeId) async {
    final db = await DatabaseService.instance.database;

    // Demote via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.removeAdmin(
        groupId: groupId,
        memberId: nodeId,
      );
      if (!success) {
        return false;
      }
    }

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

    return true;
  }

  /// Update group name (admin only)
  Future<bool> updateName(String groupId, String name) async {
    final db = await DatabaseService.instance.database;

    // Update via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.setGroupName(groupId, name);
      if (!success) {
        return false;
      }
    }

    await db.update(
      'groups',
      {
        'name': name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Update conversation display_name
    await db.update(
      'conversations',
      {'display_name': name},
      where: 'id = ?',
      whereArgs: [groupId],
    );

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Update group description
  Future<bool> updateDescription(String groupId, String? description) async {
    final db = await DatabaseService.instance.database;

    // Update via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized && description != null) {
      final success = await _ffiProvider!.setGroupDescription(groupId, description);
      if (!success) {
        return false;
      }
    }

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

    return true;
  }

  // ============================================================
  // Public API - Messaging (Database + FFI)
  // ============================================================

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

    // Send via FFI first to get the message ID
    String msgId;
    MessageStatus status;

    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = await _ffiProvider!.sendText(
        groupId: groupId,
        text: content,
        replyToMsgId: replyToId,
      );

      if (!result.success || result.msgId == null) {
        throw StateError('Failed to send message: ${result.error}');
      }
      msgId = result.msgId!;
      status = MessageStatus.sent;
    } else {
      // Fallback for testing/offline
      msgId = _uuid.v4();
      status = MessageStatus.failed;
      _log.warning('Sending local-only message (FFI not connected)',
          source: 'GroupService');
    }

    final message = Message(
      id: msgId,
      conversationId: groupId,
      senderId: identity.nodeId,
      content: content,
      timestamp: DateTime.now(),
      status: status,
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

    _messageController.add(message);
    return message;
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

  // ============================================================
  // Public API - Message Actions (Phase 2)
  // ============================================================

  /// Edit a message in group
  Future<bool> editMessage({
    required String groupId,
    required String messageId,
    required String newContent,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return false;

    // Get the original message to verify ownership
    final msgRows = await db.query(
      'messages',
      where: 'id = ? AND conversation_id = ?',
      whereArgs: [messageId, groupId],
    );
    if (msgRows.isEmpty) {
      _log.error('Message not found for edit', source: 'GroupService');
      return false;
    }

    final originalMsg = Message.fromMap(msgRows.first);

    // Only the sender can edit their own message
    if (originalMsg.senderId != identity.nodeId) {
      _log.error('Cannot edit message: not the sender', source: 'GroupService');
      return false;
    }

    // Broadcast edit via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = _ffiProvider!.bindings.groupEditMessage(
        groupId,
        messageId,
        newContent,
      );
      if (result != 0) {
        _log.error('Failed to broadcast edit via FFI: $result',
            source: 'GroupService');
        return false;
      }
    }

    // Update local database
    final now = DateTime.now();
    await db.update(
      'messages',
      {
        'original_content': originalMsg.originalContent ?? originalMsg.content,
        'content': newContent,
        'is_edited': 1,
        'edited_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    _log.info('Edited message $messageId', source: 'GroupService');

    // Emit updated message
    final updatedMsg = originalMsg.copyWith(
      content: newContent,
      isEdited: true,
      editedAt: now,
      originalContent: originalMsg.originalContent ?? originalMsg.content,
    );
    _messageController.add(updatedMsg);

    return true;
  }

  /// Delete a message from group
  Future<bool> deleteMessage({
    required String groupId,
    required String messageId,
    required bool deleteForAll,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return false;

    // Get the message
    final msgRows = await db.query(
      'messages',
      where: 'id = ? AND conversation_id = ?',
      whereArgs: [messageId, groupId],
    );
    if (msgRows.isEmpty) {
      _log.error('Message not found for delete', source: 'GroupService');
      return false;
    }

    final msg = Message.fromMap(msgRows.first);

    // For delete for all, need to be sender or have DELETE_MESSAGES permission
    if (deleteForAll && msg.senderId != identity.nodeId) {
      // Check if admin with delete permission
      final hasPermission = _ffiProvider?.bindings.groupHasPermission(
        groupId,
        identity.nodeId,
        0x04, // CYXCHAT_PERM_DELETE_MESSAGES
      );
      if (hasPermission != true) {
        _log.error('Cannot delete message for all: no permission',
            source: 'GroupService');
        return false;
      }
    }

    // Broadcast delete via FFI (only for delete for all)
    if (deleteForAll && _ffiProvider != null && _ffiProvider!.initialized) {
      final result = _ffiProvider!.bindings.groupDeleteMessage(
        groupId,
        messageId,
        deleteForAll,
      );
      if (result != 0) {
        _log.error('Failed to broadcast delete via FFI: $result',
            source: 'GroupService');
        return false;
      }
    }

    // Update local database
    final now = DateTime.now();
    await db.update(
      'messages',
      {
        'is_deleted': 1,
        'deleted_by': identity.nodeId,
        'deleted_at': now.millisecondsSinceEpoch,
        'content': '[Message deleted]',
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    _log.info('Deleted message $messageId (forAll: $deleteForAll)',
        source: 'GroupService');

    // Emit updated message
    final updatedMsg = msg.copyWith(
      isDeleted: true,
      deletedBy: identity.nodeId,
      deletedAt: now,
      content: '[Message deleted]',
    );
    _messageController.add(updatedMsg);

    return true;
  }

  /// Pin a message in group (admin only)
  Future<bool> pinMessage({
    required String groupId,
    required String messageId,
    bool notify = true,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return false;

    // Pin via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = _ffiProvider!.bindings.groupPinMessage(
        groupId,
        messageId,
        notify: notify,
      );
      if (result != 0) {
        _log.error('Failed to pin message via FFI: $result',
            source: 'GroupService');
        return false;
      }
    }

    // Save to local database
    final now = DateTime.now();
    await db.insert('pinned_messages', {
      'group_id': groupId,
      'message_id': messageId,
      'pinned_by': identity.nodeId,
      'pinned_at': now.millisecondsSinceEpoch,
    });

    _log.info('Pinned message $messageId', source: 'GroupService');

    // Notify group update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Unpin a message from group (admin only)
  Future<bool> unpinMessage({
    required String groupId,
    required String messageId,
  }) async {
    final db = await DatabaseService.instance.database;

    // Unpin via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = _ffiProvider!.bindings.groupUnpinMessage(
        groupId,
        messageId,
      );
      if (result != 0) {
        _log.error('Failed to unpin message via FFI: $result',
            source: 'GroupService');
        return false;
      }
    }

    // Remove from local database
    await db.delete(
      'pinned_messages',
      where: 'group_id = ? AND message_id = ?',
      whereArgs: [groupId, messageId],
    );

    _log.info('Unpinned message $messageId', source: 'GroupService');

    // Notify group update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Unpin all messages from group (admin only)
  Future<bool> unpinAllMessages(String groupId) async {
    final db = await DatabaseService.instance.database;

    // Unpin all via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = _ffiProvider!.bindings.groupUnpinAll(groupId);
      if (result != 0) {
        _log.error('Failed to unpin all via FFI: $result',
            source: 'GroupService');
        return false;
      }
    }

    // Remove from local database
    await db.delete(
      'pinned_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    _log.info('Unpinned all messages in group $groupId', source: 'GroupService');

    // Notify group update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Get pinned messages for a group
  Future<List<Message>> getPinnedMessages(String groupId) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery('''
      SELECT m.* FROM messages m
      INNER JOIN pinned_messages pm ON m.id = pm.message_id
      WHERE pm.group_id = ?
      ORDER BY pm.pinned_at DESC
    ''', [groupId]);

    return rows.map((row) => Message.fromMap(row)).toList();
  }

  /// Get count of pinned messages
  Future<int> getPinnedCount(String groupId) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery(
      'SELECT COUNT(*) as count FROM pinned_messages WHERE group_id = ?',
      [groupId],
    );

    return rows.first['count'] as int? ?? 0;
  }

  /// Check if a message is pinned
  Future<bool> isMessagePinned({
    required String groupId,
    required String messageId,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'pinned_messages',
      where: 'group_id = ? AND message_id = ?',
      whereArgs: [groupId, messageId],
    );

    return rows.isNotEmpty;
  }

  /// Forward a message to another group
  Future<Message?> forwardMessage({
    required String fromGroupId,
    required String toGroupId,
    required String messageId,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return null;

    // Get original message
    final msgRows = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
    if (msgRows.isEmpty) {
      _log.error('Original message not found for forward', source: 'GroupService');
      return null;
    }

    final originalMsg = Message.fromMap(msgRows.first);

    // Call FFI to generate new message ID
    String? newMsgId;
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final (result, msgId) = _ffiProvider!.bindings.groupForwardMessage(
        fromGroupId,
        toGroupId,
        messageId,
      );
      if (result != 0 || msgId == null) {
        _log.error('Failed to forward message via FFI: $result',
            source: 'GroupService');
        return null;
      }
      newMsgId = msgId;
    } else {
      newMsgId = _uuid.v4();
    }

    // Create new message with forward info
    final now = DateTime.now();
    final forwardedMsg = Message(
      id: newMsgId,
      conversationId: toGroupId,
      senderId: identity.nodeId,
      type: originalMsg.type,
      content: originalMsg.content,
      timestamp: now,
      status: MessageStatus.sent,
      isOutgoing: true,
      forwardedFrom: fromGroupId,
    );

    // Save to database
    await db.insert('messages', forwardedMsg.toMap());

    // Update conversation timestamp
    await db.update(
      'conversations',
      {'last_activity_at': now.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [toGroupId],
    );

    _log.info('Forwarded message from $fromGroupId to $toGroupId',
        source: 'GroupService');

    _messageController.add(forwardedMsg);
    return forwardedMsg;
  }

  // ============================================================
  // Public API - Key Management (FFI)
  // ============================================================

  /// Rotate group key (admin only)
  Future<bool> rotateKey(String groupId) async {
    if (_ffiProvider == null || !_ffiProvider!.initialized) {
      _log.error('Cannot rotate key: FFI not connected',
          source: 'GroupService');
      return false;
    }

    return _ffiProvider!.rotateKey(groupId);
  }

  /// Set auto-rotation on member leave
  void setAutoRotateOnLeave(bool enable) {
    _ffiProvider?.setAutoRotateOnLeave(enable);
  }

  /// Set auto-rotation on kick notification
  void setAutoRotateOnKick(bool enable) {
    _ffiProvider?.setAutoRotateOnKick(enable);
  }

  /// Get key distribution progress for a group
  KeyDistProgress? getKeyDistProgress(String groupId) {
    return _ffiProvider?.getKeyDistProgress(groupId);
  }

  // ============================================================
  // Public API - Invitations (FFI)
  // ============================================================

  /// Get pending group invites
  List<GroupInvite> get pendingInvites =>
      _ffiProvider?.pendingInvites ?? [];

  /// Accept a pending group invite
  Future<bool> acceptInvite(String groupId) async {
    if (_ffiProvider == null || !_ffiProvider!.initialized) {
      _log.error('Cannot accept invite: FFI not connected',
          source: 'GroupService');
      return false;
    }

    // Get invite details before accepting
    final invite = _ffiProvider!.pendingInvites
        .where((i) => i.groupId == groupId)
        .firstOrNull;

    final success = await _ffiProvider!.acceptInvite(groupId);
    if (!success) return false;

    // Create local group and conversation entries
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return false;

    final now = DateTime.now();
    final groupName = invite?.groupName ?? 'Group';

    // Check if group already exists
    final existing = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [groupId],
    );
    if (existing.isEmpty) {
      // Create group
      await db.insert('groups', {
        'id': groupId,
        'name': groupName,
        'creator_id': invite?.inviterId ?? '',
        'key_version': 1,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });

      // Add ourselves as member
      await db.insert('group_members', {
        'group_id': groupId,
        'node_id': identity.nodeId,
        'role': GroupRole.member.index,
        'display_name': identity.displayName,
        'joined_at': now.millisecondsSinceEpoch,
      });

      // Create conversation entry
      await db.insert('conversations', {
        'id': groupId,
        'type': 1, // ConversationType.group
        'group_id': groupId,
        'display_name': groupName,
        'is_pinned': 0,
        'is_muted': 0,
        'unread_count': 0,
        'last_activity_at': now.millisecondsSinceEpoch,
      });
    }

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Decline a pending group invite
  Future<bool> declineInvite(String groupId) async {
    if (_ffiProvider == null || !_ffiProvider!.initialized) {
      _log.error('Cannot decline invite: FFI not connected',
          source: 'GroupService');
      return false;
    }

    return _ffiProvider!.declineInvite(groupId);
  }

  // ============================================================
  // Public API - Admin Permissions (Database + FFI) - Phase 1
  // ============================================================

  /// Set granular permissions for an admin
  Future<bool> setAdminPermissions({
    required String groupId,
    required String adminId,
    required AdminPermissions permissions,
  }) async {
    final db = await DatabaseService.instance.database;

    // Set via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.setAdminPermissions(
        groupId: groupId,
        adminId: adminId,
        permissions: permissions.toBitmask(),
      );
      if (!success) {
        _log.error('Failed to set admin permissions via FFI',
            source: 'GroupService');
        return false;
      }
    }

    // Save to database
    await db.insert(
      'admin_permissions',
      permissions.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _log.info('Set permissions for admin ${adminId.substring(0, 8)}...',
        source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Get admin permissions from database
  Future<AdminPermissions?> getAdminPermissions({
    required String groupId,
    required String adminId,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'admin_permissions',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, adminId],
    );

    if (rows.isEmpty) return null;
    return AdminPermissions.fromMap(rows.first);
  }

  /// Get all admin permissions for a group
  Future<List<AdminPermissions>> getGroupAdminPermissions(String groupId) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'admin_permissions',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    return rows.map((row) => AdminPermissions.fromMap(row)).toList();
  }

  /// Check if admin has a specific permission
  bool hasPermission({
    required String groupId,
    required String adminId,
    required int permission,
  }) {
    if (_ffiProvider == null || !_ffiProvider!.initialized) {
      return false;
    }
    return _ffiProvider!.hasPermission(
      groupId: groupId,
      adminId: adminId,
      permission: permission,
    );
  }

  /// Remove admin permissions (when demoted)
  Future<bool> removeAdminPermissions({
    required String groupId,
    required String adminId,
  }) async {
    final db = await DatabaseService.instance.database;

    await db.delete(
      'admin_permissions',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, adminId],
    );

    return true;
  }

  // ============================================================
  // Public API - Member Restrictions (Database + FFI) - Phase 1
  // ============================================================

  /// Restrict a member (mute, no media, etc.)
  Future<bool> restrictMember({
    required String groupId,
    required String memberId,
    required MemberRestriction restriction,
  }) async {
    final db = await DatabaseService.instance.database;

    // Set via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.restrictMember(
        groupId: groupId,
        memberId: memberId,
        restrictions: restriction.toBitmask(),
        untilMs: restriction.mutedUntil?.millisecondsSinceEpoch,
      );
      if (!success) {
        _log.error('Failed to restrict member via FFI',
            source: 'GroupService');
        return false;
      }
    }

    // Save to database
    await db.insert(
      'member_restrictions',
      restriction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _log.info('Restricted member ${memberId.substring(0, 8)}...',
        source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Mute a member
  Future<bool> muteMember({
    required String groupId,
    required String memberId,
    required String restrictedBy,
    Duration? duration,
  }) async {
    final until = duration != null ? DateTime.now().add(duration) : null;
    final restriction = MemberRestriction.muted(
      groupId: groupId,
      nodeId: memberId,
      restrictedBy: restrictedBy,
      until: until,
    );
    return restrictMember(
      groupId: groupId,
      memberId: memberId,
      restriction: restriction,
    );
  }

  /// Unmute/unrestrict a member
  Future<bool> unrestrictMember({
    required String groupId,
    required String memberId,
  }) async {
    final db = await DatabaseService.instance.database;

    // Unrestrict via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.unrestrictMember(
        groupId: groupId,
        memberId: memberId,
      );
      if (!success) {
        _log.error('Failed to unrestrict member via FFI',
            source: 'GroupService');
        return false;
      }
    }

    // Remove from database
    await db.delete(
      'member_restrictions',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, memberId],
    );

    _log.info('Unrestricted member ${memberId.substring(0, 8)}...',
        source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Get member restriction from database
  Future<MemberRestriction?> getMemberRestriction({
    required String groupId,
    required String memberId,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'member_restrictions',
      where: 'group_id = ? AND node_id = ?',
      whereArgs: [groupId, memberId],
    );

    if (rows.isEmpty) return null;
    return MemberRestriction.fromMap(rows.first);
  }

  /// Get all member restrictions for a group
  Future<List<MemberRestriction>> getGroupRestrictions(String groupId) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'member_restrictions',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    return rows.map((row) => MemberRestriction.fromMap(row)).toList();
  }

  /// Check if member is currently muted
  bool isMemberMuted({
    required String groupId,
    required String memberId,
  }) {
    if (_ffiProvider == null || !_ffiProvider!.initialized) {
      return false;
    }
    return _ffiProvider!.isMemberMuted(
      groupId: groupId,
      memberId: memberId,
    );
  }

  // ============================================================
  // Public API - Group Settings (Database + FFI) - Phase 1
  // ============================================================

  /// Set slow mode (seconds between messages)
  Future<bool> setSlowMode({
    required String groupId,
    required int seconds,
  }) async {
    final db = await DatabaseService.instance.database;

    // Set via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.setSlowMode(
        groupId: groupId,
        seconds: seconds,
      );
      if (!success) {
        _log.error('Failed to set slow mode via FFI', source: 'GroupService');
        return false;
      }
    }

    // Update database
    await db.update(
      'groups',
      {
        'slow_mode_seconds': seconds,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    _log.info('Set slow mode to ${seconds}s', source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Set who can add members
  Future<bool> setWhoCanAddMembers({
    required String groupId,
    required WhoCanAddMembers setting,
  }) async {
    final db = await DatabaseService.instance.database;

    // Set via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.setWhoCanAdd(
        groupId: groupId,
        setting: setting.index,
      );
      if (!success) {
        _log.error('Failed to set who can add members via FFI',
            source: 'GroupService');
        return false;
      }
    }

    // Update database
    await db.update(
      'groups',
      {
        'who_can_add_members': setting.index,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    _log.info('Set who can add members to ${setting.displayName}',
        source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Set who can change group info
  Future<bool> setWhoCanChangeInfo({
    required String groupId,
    required WhoCanChangeInfo setting,
  }) async {
    final db = await DatabaseService.instance.database;

    // Set via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.setWhoCanEdit(
        groupId: groupId,
        setting: setting.index,
      );
      if (!success) {
        _log.error('Failed to set who can change info via FFI',
            source: 'GroupService');
        return false;
      }
    }

    // Update database
    await db.update(
      'groups',
      {
        'who_can_change_info': setting.index,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    _log.info('Set who can change info to ${setting.displayName}',
        source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Set message history visibility for new members
  Future<bool> setMessageHistoryVisible({
    required String groupId,
    required bool visible,
  }) async {
    final db = await DatabaseService.instance.database;

    // Update database
    await db.update(
      'groups',
      {
        'message_history_visible': visible ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    _log.info('Set message history visible to $visible',
        source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  /// Upgrade group to supergroup
  Future<bool> upgradeToSupergroup(String groupId) async {
    final db = await DatabaseService.instance.database;

    // Upgrade via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final success = await _ffiProvider!.upgradeToSupergroup(groupId);
      if (!success) {
        _log.error('Failed to upgrade to supergroup via FFI',
            source: 'GroupService');
        return false;
      }
    }

    // Update database
    await db.update(
      'groups',
      {
        'group_type': GroupType.supergroup.index,
        'max_members': 0, // Unlimited
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );

    _log.info('Upgraded group to supergroup', source: 'GroupService');

    // Notify update
    final group = await getGroup(groupId);
    if (group != null) {
      _groupUpdateController.add(group);
    }

    return true;
  }

  // ============================================================
  // Public API - Invite Links (Database + FFI) - Phase 3
  // ============================================================

  /// Create an invite link for a group
  Future<InviteLink?> createInviteLink({
    required String groupId,
    String? name,
    DateTime? expiresAt,
    int? maxUses,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      _log.error('Cannot create invite link: no identity',
          source: 'GroupService');
      return null;
    }

    String linkId;
    final now = DateTime.now();

    // Create via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final (result, linkIdHex) = _ffiProvider!.bindings.groupCreateInviteLink(
        groupId,
        name: name,
        expiresAtMs: expiresAt?.millisecondsSinceEpoch,
        maxUses: maxUses,
      );
      if (result != 0 || linkIdHex == null) {
        _log.error('Failed to create invite link via FFI: $result',
            source: 'GroupService');
        return null;
      }
      linkId = linkIdHex;
    } else {
      // Fallback for testing
      linkId = _uuid.v4().replaceAll('-', '');
    }

    final link = InviteLink(
      id: linkId,
      groupId: groupId,
      createdBy: identity.nodeId,
      createdAt: now,
      expiresAt: expiresAt,
      maxUses: maxUses,
      useCount: 0,
      isRevoked: false,
      name: name,
    );

    // Save to database
    await db.insert('group_invite_links', link.toMap());

    _log.info('Created invite link $linkId for group $groupId',
        source: 'GroupService');

    return link;
  }

  /// Revoke an invite link
  Future<bool> revokeInviteLink({
    required String groupId,
    required String linkId,
  }) async {
    final db = await DatabaseService.instance.database;

    // Revoke via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = _ffiProvider!.bindings.groupRevokeInviteLink(groupId, linkId);
      if (result != 0) {
        _log.error('Failed to revoke invite link via FFI: $result',
            source: 'GroupService');
        return false;
      }
    }

    // Update database
    await db.update(
      'group_invite_links',
      {'is_revoked': 1},
      where: 'id = ? AND group_id = ?',
      whereArgs: [linkId, groupId],
    );

    _log.info('Revoked invite link $linkId', source: 'GroupService');
    return true;
  }

  /// Join a group via invite link
  Future<bool> joinViaLink({
    required String groupId,
    required String linkId,
  }) async {
    final db = await DatabaseService.instance.database;
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      _log.error('Cannot join via link: no identity', source: 'GroupService');
      return false;
    }

    // Join via FFI
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final result = _ffiProvider!.bindings.groupJoinViaLink(groupId, linkId);
      if (result != 0) {
        _log.error('Failed to join via link FFI: $result',
            source: 'GroupService');
        return false;
      }
    }

    // Record link usage
    await db.insert('invite_link_usage', {
      'link_id': linkId,
      'node_id': identity.nodeId,
      'joined_at': DateTime.now().millisecondsSinceEpoch,
    });

    // Increment use count
    await db.rawUpdate('''
      UPDATE group_invite_links
      SET use_count = use_count + 1
      WHERE id = ?
    ''', [linkId]);

    _log.info('Joined group $groupId via link $linkId', source: 'GroupService');
    return true;
  }

  /// Get all invite links for a group
  Future<List<InviteLink>> getInviteLinks(String groupId) async {
    final db = await DatabaseService.instance.database;

    // Try FFI first for most up-to-date data
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final linksData = _ffiProvider!.bindings.groupGetInviteLinks(groupId);
      if (linksData.isNotEmpty) {
        return linksData.map((data) => InviteLink(
          id: data['id'] as String,
          groupId: data['groupId'] as String,
          createdBy: data['createdBy'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
          expiresAt: data['expiresAt'] != null && data['expiresAt'] != 0
              ? DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int)
              : null,
          maxUses: data['maxUses'] as int?,
          useCount: data['useCount'] as int? ?? 0,
          isRevoked: data['isRevoked'] as bool? ?? false,
          name: data['name'] as String?,
        )).toList();
      }
    }

    // Fallback to database
    final rows = await db.query(
      'group_invite_links',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );

    return rows.map((row) => InviteLink.fromMap(row)).toList();
  }

  /// Get a specific invite link
  Future<InviteLink?> getInviteLink({
    required String groupId,
    required String linkId,
  }) async {
    final db = await DatabaseService.instance.database;

    // Try FFI first
    if (_ffiProvider != null && _ffiProvider!.initialized) {
      final data = _ffiProvider!.bindings.groupGetInviteLink(groupId, linkId);
      if (data != null) {
        return InviteLink(
          id: data['id'] as String,
          groupId: data['groupId'] as String,
          createdBy: data['createdBy'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
          expiresAt: data['expiresAt'] != null && data['expiresAt'] != 0
              ? DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int)
              : null,
          maxUses: data['maxUses'] as int?,
          useCount: data['useCount'] as int? ?? 0,
          isRevoked: data['isRevoked'] as bool? ?? false,
          name: data['name'] as String?,
        );
      }
    }

    // Fallback to database
    final rows = await db.query(
      'group_invite_links',
      where: 'id = ? AND group_id = ?',
      whereArgs: [linkId, groupId],
    );

    if (rows.isEmpty) return null;
    return InviteLink.fromMap(rows.first);
  }

  /// Get invite link URL for sharing
  String getInviteLinkUrl({
    required String groupId,
    required String linkId,
  }) {
    return 'cyxchat://join/$groupId/$linkId';
  }

  /// Parse an invite URL
  /// Returns (groupId, linkId) or null if invalid
  ({String groupId, String linkId})? parseInviteUrl(String url) {
    final result = _ffiProvider?.bindings.groupParseInviteUrl(url);
    if (result != null) {
      return (groupId: result.$1, linkId: result.$2);
    }
    return null;
  }

  /// Get users who joined via a specific link
  Future<List<InviteLinkUsage>> getLinkUsage(String linkId) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'invite_link_usage',
      where: 'link_id = ?',
      whereArgs: [linkId],
      orderBy: 'joined_at DESC',
    );

    return rows.map((row) => InviteLinkUsage.fromMap(row)).toList();
  }

  /// Delete an invite link completely (admin only)
  Future<bool> deleteInviteLink({
    required String groupId,
    required String linkId,
  }) async {
    final db = await DatabaseService.instance.database;

    // Delete usage records first
    await db.delete(
      'invite_link_usage',
      where: 'link_id = ?',
      whereArgs: [linkId],
    );

    // Delete the link
    await db.delete(
      'group_invite_links',
      where: 'id = ? AND group_id = ?',
      whereArgs: [linkId, groupId],
    );

    _log.info('Deleted invite link $linkId', source: 'GroupService');
    return true;
  }

  // ============================================================
  // Admin Action Log (Phase 4)
  // ============================================================

  /// Log an admin action
  Future<AdminAction?> logAdminAction({
    required String groupId,
    required AdminActionType actionType,
    String? targetId,
    String? targetMessageId,
    String? oldValue,
    String? newValue,
  }) async {
    // Log via FFI
    final result = _ffiProvider?.bindings.groupLogAdminAction(
      groupId,
      actionType.value,
      targetIdHex: targetId,
      targetMsgIdHex: targetMessageId,
      oldValue: oldValue,
      newValue: newValue,
    );

    if (result == null || result.$1 != 0) {
      _log.warning('Failed to log admin action: ${result?.$1}', source: 'GroupService');
      return null;
    }

    final actionId = result.$2!;
    final now = DateTime.now();

    // Also store in database for persistence
    final db = await DatabaseService.instance.database;
    final action = AdminAction(
      id: actionId,
      groupId: groupId,
      adminId: _ffiProvider!.localNodeId!,
      actionType: actionType,
      targetId: targetId,
      targetMessageId: targetMessageId,
      oldValue: oldValue,
      newValue: newValue,
      timestamp: now,
    );

    await db.insert('admin_actions', action.toMap());

    _log.info('Logged admin action: ${actionType.description}', source: 'GroupService');
    return action;
  }

  /// Get admin actions for a group
  Future<List<AdminAction>> getAdminActions(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'admin_actions',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map((row) => AdminAction.fromMap(row)).toList();
  }

  /// Get admin actions by a specific admin
  Future<List<AdminAction>> getAdminActionsByAdmin(
    String groupId,
    String adminId, {
    int limit = 50,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'admin_actions',
      where: 'group_id = ? AND admin_id = ?',
      whereArgs: [groupId, adminId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map((row) => AdminAction.fromMap(row)).toList();
  }

  /// Get count of admin actions for a group
  Future<int> getAdminActionCount(String groupId) async {
    final db = await DatabaseService.instance.database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM admin_actions WHERE group_id = ?',
      [groupId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get admin actions filtered by type
  Future<List<AdminAction>> getAdminActionsByType(
    String groupId,
    AdminActionType actionType, {
    int limit = 50,
  }) async {
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'admin_actions',
      where: 'group_id = ? AND action_type = ?',
      whereArgs: [groupId, actionType.value],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map((row) => AdminAction.fromMap(row)).toList();
  }

  /// Delete old admin actions (for cleanup)
  Future<int> deleteOldAdminActions(
    String groupId, {
    int olderThanDays = 90,
  }) async {
    final db = await DatabaseService.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;

    return await db.delete(
      'admin_actions',
      where: 'group_id = ? AND timestamp < ?',
      whereArgs: [groupId, cutoff],
    );
  }

  // ============================================================
  // Utilities
  // ============================================================

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  void dispose() {
    disconnectProvider();
    _messageController.close();
    _groupUpdateController.close();
  }
}
