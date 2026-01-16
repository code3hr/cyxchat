import 'dart:async';
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
      'title': name,
      'is_pinned': 0,
      'is_muted': 0,
      'is_archived': 0,
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
        'title': groupName,
        'is_pinned': 0,
        'is_muted': 0,
        'is_archived': 0,
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
