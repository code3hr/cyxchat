import 'package:equatable/equatable.dart';
import 'group_member.dart';

/// Group chat entry
class Group extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String creatorId;
  final int keyVersion;
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'creator_id': creatorId,
      'key_version': keyVersion,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'last_message_text': lastMessageText,
      'last_message_at': lastMessageAt?.millisecondsSinceEpoch,
      'unread_count': unreadCount,
    };
  }

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

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        creatorId,
        keyVersion,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      members: members ?? this.members,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
