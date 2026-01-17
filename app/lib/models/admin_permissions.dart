import 'package:equatable/equatable.dart';

/// Permission flags matching C library CYXCHAT_PERM_* constants
class AdminPermissionFlags {
  static const int addMembers = 1 << 0;
  static const int removeMembers = 1 << 1;
  static const int deleteMessages = 1 << 2;
  static const int pinMessages = 1 << 3;
  static const int changeInfo = 1 << 4;
  static const int banUsers = 1 << 5;
  static const int manageAdmins = 1 << 6;
  static const int all = 0x7F;

  /// Default permissions for new admins
  static const int defaultAdmin = addMembers | removeMembers | deleteMessages | changeInfo;
}

/// Admin permissions for granular per-admin control
class AdminPermissions extends Equatable {
  final String groupId;
  final String nodeId;
  final bool canAddMembers;
  final bool canRemoveMembers;
  final bool canDeleteMessages;
  final bool canPinMessages;
  final bool canChangeInfo;
  final bool canBanUsers;
  final bool canManageAdmins;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AdminPermissions({
    required this.groupId,
    required this.nodeId,
    this.canAddMembers = true,
    this.canRemoveMembers = true,
    this.canDeleteMessages = true,
    this.canPinMessages = false,
    this.canChangeInfo = true,
    this.canBanUsers = false,
    this.canManageAdmins = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create with default admin permissions
  factory AdminPermissions.defaultAdmin({
    required String groupId,
    required String nodeId,
  }) {
    final now = DateTime.now();
    return AdminPermissions(
      groupId: groupId,
      nodeId: nodeId,
      canAddMembers: true,
      canRemoveMembers: true,
      canDeleteMessages: true,
      canPinMessages: false,
      canChangeInfo: true,
      canBanUsers: false,
      canManageAdmins: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create with all permissions (owner)
  factory AdminPermissions.owner({
    required String groupId,
    required String nodeId,
  }) {
    final now = DateTime.now();
    return AdminPermissions(
      groupId: groupId,
      nodeId: nodeId,
      canAddMembers: true,
      canRemoveMembers: true,
      canDeleteMessages: true,
      canPinMessages: true,
      canChangeInfo: true,
      canBanUsers: true,
      canManageAdmins: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory AdminPermissions.fromMap(Map<String, dynamic> map) {
    return AdminPermissions(
      groupId: map['group_id'] as String,
      nodeId: map['node_id'] as String,
      canAddMembers: (map['can_add_members'] as int? ?? 1) == 1,
      canRemoveMembers: (map['can_remove_members'] as int? ?? 1) == 1,
      canDeleteMessages: (map['can_delete_messages'] as int? ?? 1) == 1,
      canPinMessages: (map['can_pin_messages'] as int? ?? 0) == 1,
      canChangeInfo: (map['can_change_info'] as int? ?? 1) == 1,
      canBanUsers: (map['can_ban_users'] as int? ?? 0) == 1,
      canManageAdmins: (map['can_manage_admins'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'group_id': groupId,
      'node_id': nodeId,
      'can_add_members': canAddMembers ? 1 : 0,
      'can_remove_members': canRemoveMembers ? 1 : 0,
      'can_delete_messages': canDeleteMessages ? 1 : 0,
      'can_pin_messages': canPinMessages ? 1 : 0,
      'can_change_info': canChangeInfo ? 1 : 0,
      'can_ban_users': canBanUsers ? 1 : 0,
      'can_manage_admins': canManageAdmins ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// Convert to bitmask for C library
  int toBitmask() {
    int mask = 0;
    if (canAddMembers) mask |= AdminPermissionFlags.addMembers;
    if (canRemoveMembers) mask |= AdminPermissionFlags.removeMembers;
    if (canDeleteMessages) mask |= AdminPermissionFlags.deleteMessages;
    if (canPinMessages) mask |= AdminPermissionFlags.pinMessages;
    if (canChangeInfo) mask |= AdminPermissionFlags.changeInfo;
    if (canBanUsers) mask |= AdminPermissionFlags.banUsers;
    if (canManageAdmins) mask |= AdminPermissionFlags.manageAdmins;
    return mask;
  }

  /// Create from bitmask
  factory AdminPermissions.fromBitmask({
    required String groupId,
    required String nodeId,
    required int bitmask,
  }) {
    final now = DateTime.now();
    return AdminPermissions(
      groupId: groupId,
      nodeId: nodeId,
      canAddMembers: (bitmask & AdminPermissionFlags.addMembers) != 0,
      canRemoveMembers: (bitmask & AdminPermissionFlags.removeMembers) != 0,
      canDeleteMessages: (bitmask & AdminPermissionFlags.deleteMessages) != 0,
      canPinMessages: (bitmask & AdminPermissionFlags.pinMessages) != 0,
      canChangeInfo: (bitmask & AdminPermissionFlags.changeInfo) != 0,
      canBanUsers: (bitmask & AdminPermissionFlags.banUsers) != 0,
      canManageAdmins: (bitmask & AdminPermissionFlags.manageAdmins) != 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Check if has all permissions
  bool get hasAllPermissions =>
      canAddMembers &&
      canRemoveMembers &&
      canDeleteMessages &&
      canPinMessages &&
      canChangeInfo &&
      canBanUsers &&
      canManageAdmins;

  /// Get list of permission names that are enabled
  List<String> get enabledPermissions {
    final permissions = <String>[];
    if (canAddMembers) permissions.add('Add Members');
    if (canRemoveMembers) permissions.add('Remove Members');
    if (canDeleteMessages) permissions.add('Delete Messages');
    if (canPinMessages) permissions.add('Pin Messages');
    if (canChangeInfo) permissions.add('Change Info');
    if (canBanUsers) permissions.add('Ban Users');
    if (canManageAdmins) permissions.add('Manage Admins');
    return permissions;
  }

  @override
  List<Object?> get props => [
        groupId,
        nodeId,
        canAddMembers,
        canRemoveMembers,
        canDeleteMessages,
        canPinMessages,
        canChangeInfo,
        canBanUsers,
        canManageAdmins,
        createdAt,
        updatedAt,
      ];

  AdminPermissions copyWith({
    String? groupId,
    String? nodeId,
    bool? canAddMembers,
    bool? canRemoveMembers,
    bool? canDeleteMessages,
    bool? canPinMessages,
    bool? canChangeInfo,
    bool? canBanUsers,
    bool? canManageAdmins,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AdminPermissions(
      groupId: groupId ?? this.groupId,
      nodeId: nodeId ?? this.nodeId,
      canAddMembers: canAddMembers ?? this.canAddMembers,
      canRemoveMembers: canRemoveMembers ?? this.canRemoveMembers,
      canDeleteMessages: canDeleteMessages ?? this.canDeleteMessages,
      canPinMessages: canPinMessages ?? this.canPinMessages,
      canChangeInfo: canChangeInfo ?? this.canChangeInfo,
      canBanUsers: canBanUsers ?? this.canBanUsers,
      canManageAdmins: canManageAdmins ?? this.canManageAdmins,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
