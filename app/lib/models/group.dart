import 'package:equatable/equatable.dart';
import 'group_member.dart';

/// Group type enum
enum GroupType {
  basic,      // Basic group: 200 members max, simpler features
  supergroup; // Supergroup: unlimited members, full admin features

  String get displayName {
    switch (this) {
      case GroupType.basic:
        return 'Basic Group';
      case GroupType.supergroup:
        return 'Supergroup';
    }
  }

  static GroupType fromInt(int value) {
    if (value >= 0 && value < GroupType.values.length) {
      return GroupType.values[value];
    }
    return GroupType.basic;
  }
}

/// Who can add members setting
enum WhoCanAddMembers {
  everyone,   // All members can add members
  adminsOnly; // Only admins can add members

  String get displayName {
    switch (this) {
      case WhoCanAddMembers.everyone:
        return 'Everyone';
      case WhoCanAddMembers.adminsOnly:
        return 'Admins Only';
    }
  }

  static WhoCanAddMembers fromInt(int value) {
    if (value >= 0 && value < WhoCanAddMembers.values.length) {
      return WhoCanAddMembers.values[value];
    }
    return WhoCanAddMembers.everyone;
  }
}

/// Who can change info setting
enum WhoCanChangeInfo {
  everyone,   // All members can edit group info
  adminsOnly; // Only admins can edit group info

  String get displayName {
    switch (this) {
      case WhoCanChangeInfo.everyone:
        return 'Everyone';
      case WhoCanChangeInfo.adminsOnly:
        return 'Admins Only';
    }
  }

  static WhoCanChangeInfo fromInt(int value) {
    if (value >= 0 && value < WhoCanChangeInfo.values.length) {
      return WhoCanChangeInfo.values[value];
    }
    return WhoCanChangeInfo.everyone;
  }
}

/// Who can send messages setting
enum WhoCanSendMessages {
  everyone,       // All members can send messages (default)
  adminsOnly,     // Only admins can send (broadcast/channel mode)
  selectedOnly;   // Only selected members can send

  String get displayName {
    switch (this) {
      case WhoCanSendMessages.everyone:
        return 'Everyone';
      case WhoCanSendMessages.adminsOnly:
        return 'Admins Only';
      case WhoCanSendMessages.selectedOnly:
        return 'Selected Members';
    }
  }

  String get description {
    switch (this) {
      case WhoCanSendMessages.everyone:
        return 'All members can send messages';
      case WhoCanSendMessages.adminsOnly:
        return 'Only admins can send messages (broadcast mode)';
      case WhoCanSendMessages.selectedOnly:
        return 'Only selected members can send messages';
    }
  }

  static WhoCanSendMessages fromInt(int value) {
    if (value >= 0 && value < WhoCanSendMessages.values.length) {
      return WhoCanSendMessages.values[value];
    }
    return WhoCanSendMessages.everyone;
  }
}

/// Group chat entry
class Group extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String creatorId;
  final int keyVersion;
  final GroupType groupType;
  final WhoCanAddMembers whoCanAddMembers;
  final WhoCanChangeInfo whoCanChangeInfo;
  final WhoCanSendMessages whoCanSend;
  final List<String> selectedSenders;  // Node IDs of selected senders
  final bool messageHistoryVisible;
  final int slowModeSeconds;
  final int maxMembers;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GroupMember> members;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const Group({
    required this.id,
    required this.name,
    this.description,
    required this.creatorId,
    this.keyVersion = 1,
    this.groupType = GroupType.basic,
    this.whoCanAddMembers = WhoCanAddMembers.everyone,
    this.whoCanChangeInfo = WhoCanChangeInfo.adminsOnly,
    this.whoCanSend = WhoCanSendMessages.everyone,
    this.selectedSenders = const [],
    this.messageHistoryVisible = true,
    this.slowModeSeconds = 0,
    this.maxMembers = 200,
    required this.createdAt,
    required this.updatedAt,
    this.members = const [],
    this.lastMessageText,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory Group.fromMap(Map<String, dynamic> map) {
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      creatorId: map['creator_id'] as String,
      keyVersion: map['key_version'] as int? ?? 1,
      groupType: GroupType.fromInt(map['group_type'] as int? ?? 0),
      whoCanAddMembers: WhoCanAddMembers.fromInt(map['who_can_add_members'] as int? ?? 0),
      whoCanChangeInfo: WhoCanChangeInfo.fromInt(map['who_can_change_info'] as int? ?? 1),
      whoCanSend: WhoCanSendMessages.fromInt(map['who_can_send'] as int? ?? 0),
      selectedSenders: (map['selected_senders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      messageHistoryVisible: (map['message_history_visible'] as int? ?? 1) == 1,
      slowModeSeconds: map['slow_mode_seconds'] as int? ?? 0,
      maxMembers: map['max_members'] as int? ?? 200,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      members: [],
      lastMessageText: map['last_message_text'] as String?,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int)
          : null,
      unreadCount: map['unread_count'] as int? ?? 0,
    );
  }

  /// Convert to map for database insertion
  /// Note: last_message_text, last_message_at, unread_count are computed from
  /// messages table via JOIN query, not stored in groups table
  /// Note: selected_senders is stored in separate table, not included here
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'creator_id': creatorId,
      'key_version': keyVersion,
      'group_type': groupType.index,
      'who_can_add_members': whoCanAddMembers.index,
      'who_can_change_info': whoCanChangeInfo.index,
      'who_can_send': whoCanSend.index,
      'message_history_visible': messageHistoryVisible ? 1 : 0,
      'slow_mode_seconds': slowModeSeconds,
      'max_members': maxMembers,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// Check if this is a supergroup
  bool get isSupergroup => groupType == GroupType.supergroup;

  // ============================================================
  // Feature availability based on group type
  // ============================================================

  /// Max members allowed (200 for basic, unlimited for supergroup)
  int get effectiveMaxMembers => isSupergroup ? 100000 : 200;

  /// Whether granular admin permissions are available
  bool get hasGranularPermissions => isSupergroup;

  /// Whether admin action log is available
  bool get hasAdminLog => isSupergroup;

  /// Whether advanced invite links (with expiry/usage limits) are available
  bool get hasAdvancedInviteLinks => isSupergroup;

  /// Whether this group can accept more members
  bool get canAcceptMoreMembers => memberCount < effectiveMaxMembers;

  /// Check if group can be upgraded to supergroup
  bool get canUpgradeToSupergroup => !isSupergroup;

  int get memberCount => members.length;

  String get shortId => id.length >= 8 ? id.substring(0, 8) : id;

  bool isOwner(String nodeId) => creatorId == nodeId;

  bool isMember(String nodeId) =>
      members.any((member) => member.nodeId == nodeId);

  bool isAdmin(String nodeId) {
    final member = members.firstWhere(
      (m) => m.nodeId == nodeId,
      orElse: () => GroupMember(
        groupId: id,
        nodeId: nodeId,
        role: GroupRole.member,
        joinedAt: DateTime.now(),
      ),
    );
    return member.isAdmin;
  }

  GroupRole getRole(String nodeId) {
    final member = members.firstWhere(
      (m) => m.nodeId == nodeId,
      orElse: () => GroupMember(
        groupId: id,
        nodeId: nodeId,
        role: GroupRole.member,
        joinedAt: DateTime.now(),
      ),
    );
    return member.role;
  }

  GroupMember? getMember(String nodeId) {
    try {
      return members.firstWhere((m) => m.nodeId == nodeId);
    } catch (_) {
      return null;
    }
  }

  /// Check if a user can add members based on group settings
  bool canUserAddMembers(String nodeId) {
    if (isOwner(nodeId)) return true;
    if (whoCanAddMembers == WhoCanAddMembers.everyone) return true;
    return isAdmin(nodeId);
  }

  /// Check if a user can change group info based on group settings
  bool canUserChangeInfo(String nodeId) {
    if (isOwner(nodeId)) return true;
    if (whoCanChangeInfo == WhoCanChangeInfo.everyone) return true;
    return isAdmin(nodeId);
  }

  /// Check if a user can send messages based on group settings
  bool canUserSend(String nodeId) {
    // Owner and admins can always send
    if (isOwner(nodeId) || isAdmin(nodeId)) return true;

    switch (whoCanSend) {
      case WhoCanSendMessages.everyone:
        return true;
      case WhoCanSendMessages.adminsOnly:
        return false; // Already checked above
      case WhoCanSendMessages.selectedOnly:
        return selectedSenders.contains(nodeId);
    }
  }

  /// Check if a member is a selected sender
  bool isSelectedSender(String nodeId) => selectedSenders.contains(nodeId);

  /// Format slow mode for display
  String get slowModeDisplay {
    if (slowModeSeconds == 0) return 'Off';
    if (slowModeSeconds < 60) return '${slowModeSeconds}s';
    if (slowModeSeconds < 3600) return '${slowModeSeconds ~/ 60}m';
    return '${slowModeSeconds ~/ 3600}h';
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        creatorId,
        keyVersion,
        groupType,
        whoCanAddMembers,
        whoCanChangeInfo,
        whoCanSend,
        selectedSenders,
        messageHistoryVisible,
        slowModeSeconds,
        maxMembers,
        createdAt,
        updatedAt,
        members,
        lastMessageText,
        lastMessageAt,
        unreadCount,
      ];

  Group copyWith({
    String? id,
    String? name,
    String? description,
    String? creatorId,
    int? keyVersion,
    GroupType? groupType,
    WhoCanAddMembers? whoCanAddMembers,
    WhoCanChangeInfo? whoCanChangeInfo,
    WhoCanSendMessages? whoCanSend,
    List<String>? selectedSenders,
    bool? messageHistoryVisible,
    int? slowModeSeconds,
    int? maxMembers,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GroupMember>? members,
    String? lastMessageText,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      creatorId: creatorId ?? this.creatorId,
      keyVersion: keyVersion ?? this.keyVersion,
      groupType: groupType ?? this.groupType,
      whoCanAddMembers: whoCanAddMembers ?? this.whoCanAddMembers,
      whoCanChangeInfo: whoCanChangeInfo ?? this.whoCanChangeInfo,
      whoCanSend: whoCanSend ?? this.whoCanSend,
      selectedSenders: selectedSenders ?? this.selectedSenders,
      messageHistoryVisible: messageHistoryVisible ?? this.messageHistoryVisible,
      slowModeSeconds: slowModeSeconds ?? this.slowModeSeconds,
      maxMembers: maxMembers ?? this.maxMembers,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      members: members ?? this.members,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
