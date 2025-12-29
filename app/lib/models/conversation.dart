import 'package:equatable/equatable.dart';
import 'message.dart';

/// Conversation type
enum ConversationType {
  direct,
  group;

  static ConversationType fromInt(int value) {
    if (value >= 0 && value < ConversationType.values.length) {
      return ConversationType.values[value];
    }
    return ConversationType.direct;
  }
}

/// Conversation with another user or group
class Conversation extends Equatable {
  final String id;
  final ConversationType type;
  final String? peerId; // For direct chats
  final String? groupId; // For group chats
  final String? displayName;
  final String? avatarUrl;
  final Message? lastMessage;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final DateTime? lastActivityAt;

  const Conversation({
    required this.id,
    required this.type,
    this.peerId,
    this.groupId,
    this.displayName,
    this.avatarUrl,
    this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.lastActivityAt,
  });

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      type: ConversationType.fromInt(map['type'] as int? ?? 0),
      peerId: map['peer_id'] as String?,
      groupId: map['group_id'] as String?,
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      lastMessage: map['last_message'] != null
          ? Message.fromMap(map['last_message'] as Map<String, dynamic>)
          : null,
      unreadCount: map['unread_count'] as int? ?? 0,
      isPinned: (map['is_pinned'] as int?) == 1,
      isMuted: (map['is_muted'] as int?) == 1,
      lastActivityAt: map['last_activity_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_activity_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.index,
      'peer_id': peerId,
      'group_id': groupId,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'unread_count': unreadCount,
      'is_pinned': isPinned ? 1 : 0,
      'is_muted': isMuted ? 1 : 0,
      'last_activity_at': lastActivityAt?.millisecondsSinceEpoch,
    };
  }

  /// Get title for display
  String get title => displayName ?? peerId?.substring(0, 8) ?? 'Unknown';

  /// Get subtitle (last message preview)
  String get subtitle {
    if (lastMessage == null) return '';
    if (lastMessage!.isDeleted) return 'Message deleted';
    if (lastMessage!.type == MessageType.image) return '📷 Photo';
    if (lastMessage!.type == MessageType.file) return '📎 File';
    if (lastMessage!.type == MessageType.audio) return '🎤 Voice message';
    return lastMessage!.content;
  }

  /// Get last activity time string
  String get lastActivityString {
    if (lastActivityAt == null) return '';

    final now = DateTime.now();
    final diff = now.difference(lastActivityAt!);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';

    return '${lastActivityAt!.month}/${lastActivityAt!.day}';
  }

  bool get isDirect => type == ConversationType.direct;
  bool get isGroup => type == ConversationType.group;

  @override
  List<Object?> get props => [
        id,
        type,
        peerId,
        groupId,
        displayName,
        avatarUrl,
        lastMessage,
        unreadCount,
        isPinned,
        isMuted,
        lastActivityAt,
      ];

  Conversation copyWith({
    String? id,
    ConversationType? type,
    String? peerId,
    String? groupId,
    String? displayName,
    String? avatarUrl,
    Message? lastMessage,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    DateTime? lastActivityAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      peerId: peerId ?? this.peerId,
      groupId: groupId ?? this.groupId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    );
  }
}
