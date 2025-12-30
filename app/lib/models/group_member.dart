import 'package:equatable/equatable.dart';

/// Group member role
enum GroupRole {
  member,
  admin,
  owner;

  String get displayName {
    switch (this) {
      case GroupRole.member:
        return 'Member';
      case GroupRole.admin:
        return 'Admin';
      case GroupRole.owner:
        return 'Owner';
    }
  }

  static GroupRole fromInt(int value) {
    if (value >= 0 && value < GroupRole.values.length) {
      return GroupRole.values[value];
    }
    return GroupRole.member;
  }
}

/// Group member entry
class GroupMember extends Equatable {
  final String groupId;
  final String nodeId;
  final GroupRole role;
  final String? displayName;
  final DateTime joinedAt;

  const GroupMember({
    required this.groupId,
    required this.nodeId,
    required this.role,
    this.displayName,
    required this.joinedAt,
  });

  factory GroupMember.fromMap(Map<String, dynamic> map) {
    return GroupMember(
      groupId: map['group_id'] as String,
      nodeId: map['node_id'] as String,
      role: GroupRole.fromInt(map['role'] as int? ?? 0),
      displayName: map['display_name'] as String?,
      joinedAt: DateTime.fromMillisecondsSinceEpoch(map['joined_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'group_id': groupId,
      'node_id': nodeId,
      'role': role.index,
      'display_name': displayName,
      'joined_at': joinedAt.millisecondsSinceEpoch,
    };
  }

  String get shortId => nodeId.length >= 8 ? nodeId.substring(0, 8) : nodeId;

  String get displayText => displayName ?? shortId;

  bool get isAdmin => role == GroupRole.admin || role == GroupRole.owner;

  bool get isOwner => role == GroupRole.owner;

  @override
  List<Object?> get props => [
        groupId,
        nodeId,
        role,
        displayName,
        joinedAt,
      ];

  GroupMember copyWith({
    String? groupId,
    String? nodeId,
    GroupRole? role,
    String? displayName,
    DateTime? joinedAt,
  }) {
    return GroupMember(
      groupId: groupId ?? this.groupId,
      nodeId: nodeId ?? this.nodeId,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }
}
