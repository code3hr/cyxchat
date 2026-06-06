import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/group_service.dart';
import 'conversation_provider.dart';

/// Provider for the GroupService instance
final groupServiceProvider = Provider((ref) => GroupService.instance);

/// Provider for all groups
final groupsProvider = FutureProvider<List<Group>>((ref) async {
  return GroupService.instance.getGroups();
});

/// Provider for a specific group
final groupProvider = FutureProvider.family<Group?, String>((ref, groupId) async {
  return GroupService.instance.getGroup(groupId);
});

/// Provider for group members
final groupMembersProvider =
    FutureProvider.family<List<GroupMember>, String>((ref, groupId) async {
  return GroupService.instance.getGroupMembers(groupId);
});

/// Provider for messages in a group
final groupMessagesProvider =
    FutureProvider.family<List<Message>, String>((ref, groupId) async {
  return GroupService.instance.getMessages(groupId);
});

/// Provider for group message stream
final groupMessageStreamProvider = StreamProvider<Message>((ref) {
  return GroupService.instance.messageStream;
});

/// Provider for group update stream
final groupUpdateStreamProvider = StreamProvider<Group>((ref) {
  return GroupService.instance.groupUpdateStream;
});

/// Provider for pinned messages in a group
final pinnedMessagesProvider =
    FutureProvider.family<List<Message>, String>((ref, groupId) async {
  return GroupService.instance.getPinnedMessages(groupId);
});

/// Provider for pinned messages count in a group
final pinnedMessagesCountProvider =
    FutureProvider.family<int, String>((ref, groupId) async {
  return GroupService.instance.getPinnedCount(groupId);
});

/// Provider for group actions
final groupActionsProvider = Provider((ref) => GroupActions(ref));

class GroupActions {
  final Ref _ref;

  GroupActions(this._ref);

  /// Create a new group
  Future<Group> createGroup(String name, {String? description}) async {
    final group = await GroupService.instance.createGroup(
      name,
      description: description,
    );
    _ref.invalidate(groupsProvider);
    _ref.invalidate(conversationsProvider);  // Refresh home screen
    return group;
  }

  /// Send message to group
  Future<Message> sendMessage({
    required String groupId,
    required String content,
    String? replyToId,
  }) async {
    final message = await GroupService.instance.sendMessage(
      groupId,
      content,
      replyToId: replyToId,
    );
    _ref.invalidate(groupMessagesProvider(groupId));
    _ref.invalidate(groupsProvider);
    return message;
  }

  Future<Message> sendFile({
    required String groupId,
    required String filename,
    required List<int> fileData,
    String? localPath,
  }) async {
    final message = await GroupService.instance.sendFile(
      groupId: groupId,
      filename: filename,
      fileData: fileData,
      localPath: localPath,
    );
    _ref.invalidate(groupMessagesProvider(groupId));
    _ref.invalidate(groupsProvider);
    return message;
  }

  Future<Message> sendImage({
    required String groupId,
    required String filename,
    required List<int> imageData,
    required int width,
    required int height,
    String? localPath,
  }) async {
    final message = await GroupService.instance.sendImage(
      groupId: groupId,
      filename: filename,
      imageData: imageData,
      width: width,
      height: height,
      localPath: localPath,
    );
    _ref.invalidate(groupMessagesProvider(groupId));
    _ref.invalidate(groupsProvider);
    return message;
  }

  Future<Message> sendVoice({
    required String groupId,
    required List<int> audioData,
    required int durationMs,
    String? filename,
    String? localPath,
  }) async {
    final message = await GroupService.instance.sendVoice(
      groupId: groupId,
      audioData: audioData,
      durationMs: durationMs,
      filename: filename,
      localPath: localPath,
    );
    _ref.invalidate(groupMessagesProvider(groupId));
    _ref.invalidate(groupsProvider);
    return message;
  }

  /// Invite contact to group
  Future<void> inviteMember(String groupId, String nodeId) async {
    await GroupService.instance.inviteMember(groupId, nodeId);
    _ref.invalidate(groupProvider(groupId));
    _ref.invalidate(groupMembersProvider(groupId));
  }

  /// Remove member from group
  Future<void> removeMember(String groupId, String nodeId) async {
    await GroupService.instance.removeMember(groupId, nodeId);
    _ref.invalidate(groupProvider(groupId));
    _ref.invalidate(groupMembersProvider(groupId));
  }

  /// Leave group
  Future<void> leaveGroup(String groupId) async {
    await GroupService.instance.leaveGroup(groupId);
    _ref.invalidate(groupsProvider);
    _ref.invalidate(conversationsProvider);  // Refresh home screen
  }

  /// Promote member to admin
  Future<void> promoteAdmin(String groupId, String nodeId) async {
    await GroupService.instance.promoteAdmin(groupId, nodeId);
    _ref.invalidate(groupProvider(groupId));
    _ref.invalidate(groupMembersProvider(groupId));
  }

  /// Demote admin to member
  Future<void> demoteAdmin(String groupId, String nodeId) async {
    await GroupService.instance.demoteAdmin(groupId, nodeId);
    _ref.invalidate(groupProvider(groupId));
    _ref.invalidate(groupMembersProvider(groupId));
  }

  /// Update group name
  Future<void> updateName(String groupId, String name) async {
    await GroupService.instance.updateName(groupId, name);
    _ref.invalidate(groupProvider(groupId));
    _ref.invalidate(groupsProvider);
  }

  /// Update group description
  Future<void> updateDescription(String groupId, String? description) async {
    await GroupService.instance.updateDescription(groupId, description);
    _ref.invalidate(groupProvider(groupId));
  }

  /// Mark group messages as read
  Future<void> markAsRead(String groupId) async {
    await GroupService.instance.markAsRead(groupId);
    _ref.invalidate(groupsProvider);
  }

  /// Upgrade a basic group to supergroup (owner only)
  /// Returns true on success
  Future<bool> upgradeToSupergroup(String groupId) async {
    final success = await GroupService.instance.upgradeToSupergroup(groupId);
    if (success) {
      _ref.invalidate(groupProvider(groupId));
      _ref.invalidate(groupsProvider);
    }
    return success;
  }
}
