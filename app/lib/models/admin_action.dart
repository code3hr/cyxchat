/// Admin action types for audit log
enum AdminActionType {
  kick(0, 'Kicked member'),
  ban(1, 'Banned member'),
  unban(2, 'Unbanned member'),
  promote(3, 'Promoted to admin'),
  demote(4, 'Demoted admin'),
  permissionsChanged(5, 'Changed permissions'),
  restrictionsChanged(6, 'Changed restrictions'),
  messageDeleted(7, 'Deleted message'),
  messagePinned(8, 'Pinned message'),
  messageUnpinned(9, 'Unpinned message'),
  infoChanged(10, 'Changed group info'),
  slowModeChanged(11, 'Changed slow mode'),
  linkCreated(12, 'Created invite link'),
  linkRevoked(13, 'Revoked invite link'),
  memberInvited(14, 'Member joined via link');

  final int value;
  final String description;

  const AdminActionType(this.value, this.description);

  static AdminActionType fromValue(int value) {
    return AdminActionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AdminActionType.infoChanged,
    );
  }

  /// Get icon for this action type
  String get icon {
    switch (this) {
      case AdminActionType.kick:
        return '🚫';
      case AdminActionType.ban:
        return '⛔';
      case AdminActionType.unban:
        return '✅';
      case AdminActionType.promote:
        return '⬆️';
      case AdminActionType.demote:
        return '⬇️';
      case AdminActionType.permissionsChanged:
        return '🔐';
      case AdminActionType.restrictionsChanged:
        return '🔒';
      case AdminActionType.messageDeleted:
        return '🗑️';
      case AdminActionType.messagePinned:
        return '📌';
      case AdminActionType.messageUnpinned:
        return '📍';
      case AdminActionType.infoChanged:
        return 'ℹ️';
      case AdminActionType.slowModeChanged:
        return '⏱️';
      case AdminActionType.linkCreated:
        return '🔗';
      case AdminActionType.linkRevoked:
        return '🔗';
      case AdminActionType.memberInvited:
        return '👋';
    }
  }
}

/// Admin action log entry
class AdminAction {
  /// Unique action ID (16 bytes as hex string = 32 chars)
  final String id;

  /// Group this action belongs to
  final String groupId;

  /// Admin who performed the action (node ID)
  final String adminId;

  /// Type of action performed
  final AdminActionType actionType;

  /// Target user (for kick/ban/promote/etc)
  final String? targetId;

  /// Target message (for delete/pin actions)
  final String? targetMessageId;

  /// Previous value (for change actions)
  final String? oldValue;

  /// New value (for change actions)
  final String? newValue;

  /// When the action occurred
  final DateTime timestamp;

  AdminAction({
    required this.id,
    required this.groupId,
    required this.adminId,
    required this.actionType,
    this.targetId,
    this.targetMessageId,
    this.oldValue,
    this.newValue,
    required this.timestamp,
  });

  /// Create from database map
  factory AdminAction.fromMap(Map<String, dynamic> map) {
    return AdminAction(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      adminId: map['admin_id'] as String,
      actionType: AdminActionType.fromValue(map['action_type'] as int),
      targetId: map['target_id'] as String?,
      targetMessageId: map['target_message_id'] as String?,
      oldValue: map['old_value'] as String?,
      newValue: map['new_value'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'admin_id': adminId,
      'action_type': actionType.value,
      'target_id': targetId,
      'target_message_id': targetMessageId,
      'old_value': oldValue,
      'new_value': newValue,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Get a human-readable description of the action
  String getDescription({String? adminName, String? targetName}) {
    final admin = adminName ?? 'Admin';
    final target = targetName ?? 'User';

    switch (actionType) {
      case AdminActionType.kick:
        return '$admin kicked $target';
      case AdminActionType.ban:
        return '$admin banned $target';
      case AdminActionType.unban:
        return '$admin unbanned $target';
      case AdminActionType.promote:
        return '$admin promoted $target to admin';
      case AdminActionType.demote:
        return '$admin demoted $target to member';
      case AdminActionType.permissionsChanged:
        return '$admin changed permissions for $target';
      case AdminActionType.restrictionsChanged:
        return '$admin changed restrictions for $target';
      case AdminActionType.messageDeleted:
        return '$admin deleted a message';
      case AdminActionType.messagePinned:
        return '$admin pinned a message';
      case AdminActionType.messageUnpinned:
        return '$admin unpinned a message';
      case AdminActionType.infoChanged:
        if (oldValue != null && newValue != null) {
          return '$admin changed group info from "$oldValue" to "$newValue"';
        }
        return '$admin changed group info';
      case AdminActionType.slowModeChanged:
        if (newValue == '0') {
          return '$admin disabled slow mode';
        }
        return '$admin set slow mode to ${newValue}s';
      case AdminActionType.linkCreated:
        return '$admin created an invite link';
      case AdminActionType.linkRevoked:
        return '$admin revoked an invite link';
      case AdminActionType.memberInvited:
        return '$target joined via invite link';
    }
  }

  @override
  String toString() => 'AdminAction(id: $id, type: ${actionType.description})';
}
