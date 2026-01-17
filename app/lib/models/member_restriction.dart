import 'package:equatable/equatable.dart';

/// Restriction flags matching C library CYXCHAT_RESTRICT_* constants
class RestrictionFlags {
  static const int muted = 1 << 0;
  static const int noMedia = 1 << 1;
  static const int noLinks = 1 << 2;
  static const int noMessages = 1 << 3;
}

/// Member restrictions (mute, media/link restrictions, slow mode)
class MemberRestriction extends Equatable {
  final String groupId;
  final String nodeId;
  final bool isMuted;
  final DateTime? mutedUntil;
  final bool canSendMedia;
  final bool canSendLinks;
  final bool canSendMessages;
  final int slowModeSeconds;
  final DateTime? lastMessageAt;
  final String? restrictedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MemberRestriction({
    required this.groupId,
    required this.nodeId,
    this.isMuted = false,
    this.mutedUntil,
    this.canSendMedia = true,
    this.canSendLinks = true,
    this.canSendMessages = true,
    this.slowModeSeconds = 0,
    this.lastMessageAt,
    this.restrictedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create with no restrictions
  factory MemberRestriction.none({
    required String groupId,
    required String nodeId,
  }) {
    final now = DateTime.now();
    return MemberRestriction(
      groupId: groupId,
      nodeId: nodeId,
      isMuted: false,
      canSendMedia: true,
      canSendLinks: true,
      canSendMessages: true,
      slowModeSeconds: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create fully muted restriction
  factory MemberRestriction.muted({
    required String groupId,
    required String nodeId,
    required String restrictedBy,
    DateTime? until,
  }) {
    final now = DateTime.now();
    return MemberRestriction(
      groupId: groupId,
      nodeId: nodeId,
      isMuted: true,
      mutedUntil: until,
      canSendMedia: false,
      canSendLinks: false,
      canSendMessages: false,
      restrictedBy: restrictedBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory MemberRestriction.fromMap(Map<String, dynamic> map) {
    return MemberRestriction(
      groupId: map['group_id'] as String,
      nodeId: map['node_id'] as String,
      isMuted: (map['is_muted'] as int? ?? 0) == 1,
      mutedUntil: map['muted_until'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['muted_until'] as int)
          : null,
      canSendMedia: (map['can_send_media'] as int? ?? 1) == 1,
      canSendLinks: (map['can_send_links'] as int? ?? 1) == 1,
      canSendMessages: (map['can_send_messages'] as int? ?? 1) == 1,
      slowModeSeconds: map['slow_mode_seconds'] as int? ?? 0,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int)
          : null,
      restrictedBy: map['restricted_by'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'group_id': groupId,
      'node_id': nodeId,
      'is_muted': isMuted ? 1 : 0,
      'muted_until': mutedUntil?.millisecondsSinceEpoch,
      'can_send_media': canSendMedia ? 1 : 0,
      'can_send_links': canSendLinks ? 1 : 0,
      'can_send_messages': canSendMessages ? 1 : 0,
      'slow_mode_seconds': slowModeSeconds,
      'last_message_at': lastMessageAt?.millisecondsSinceEpoch,
      'restricted_by': restrictedBy,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// Convert to bitmask for C library
  int toBitmask() {
    int mask = 0;
    if (isMuted) mask |= RestrictionFlags.muted;
    if (!canSendMedia) mask |= RestrictionFlags.noMedia;
    if (!canSendLinks) mask |= RestrictionFlags.noLinks;
    if (!canSendMessages) mask |= RestrictionFlags.noMessages;
    return mask;
  }

  /// Create from bitmask
  factory MemberRestriction.fromBitmask({
    required String groupId,
    required String nodeId,
    required int bitmask,
    DateTime? mutedUntil,
    String? restrictedBy,
  }) {
    final now = DateTime.now();
    return MemberRestriction(
      groupId: groupId,
      nodeId: nodeId,
      isMuted: (bitmask & RestrictionFlags.muted) != 0,
      mutedUntil: mutedUntil,
      canSendMedia: (bitmask & RestrictionFlags.noMedia) == 0,
      canSendLinks: (bitmask & RestrictionFlags.noLinks) == 0,
      canSendMessages: (bitmask & RestrictionFlags.noMessages) == 0,
      restrictedBy: restrictedBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Check if member has any active restrictions
  bool get hasRestrictions =>
      isMuted || !canSendMedia || !canSendLinks || !canSendMessages;

  /// Check if mute has expired
  bool get isMuteExpired {
    if (!isMuted) return true;
    if (mutedUntil == null) return false; // Permanent mute
    return DateTime.now().isAfter(mutedUntil!);
  }

  /// Check if member is currently muted (not expired)
  bool get isCurrentlyMuted => isMuted && !isMuteExpired;

  /// Get remaining mute duration
  Duration? get remainingMuteDuration {
    if (!isMuted || mutedUntil == null) return null;
    final remaining = mutedUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Check if slow mode delay is active
  bool get isSlowModeActive {
    if (slowModeSeconds == 0 || lastMessageAt == null) return false;
    final nextAllowedTime = lastMessageAt!.add(Duration(seconds: slowModeSeconds));
    return DateTime.now().isBefore(nextAllowedTime);
  }

  /// Get remaining slow mode duration
  Duration? get remainingSlowModeDuration {
    if (slowModeSeconds == 0 || lastMessageAt == null) return null;
    final nextAllowedTime = lastMessageAt!.add(Duration(seconds: slowModeSeconds));
    final remaining = nextAllowedTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Get list of active restriction names
  List<String> get activeRestrictions {
    final restrictions = <String>[];
    if (isMuted) {
      if (mutedUntil != null) {
        restrictions.add('Muted until ${_formatDateTime(mutedUntil!)}');
      } else {
        restrictions.add('Muted permanently');
      }
    }
    if (!canSendMedia) restrictions.add('Cannot send media');
    if (!canSendLinks) restrictions.add('Cannot send links');
    if (!canSendMessages) restrictions.add('Cannot send messages');
    if (slowModeSeconds > 0) {
      restrictions.add('Slow mode: ${_formatDuration(slowModeSeconds)}');
    }
    return restrictions;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    return '${seconds ~/ 86400}d';
  }

  @override
  List<Object?> get props => [
        groupId,
        nodeId,
        isMuted,
        mutedUntil,
        canSendMedia,
        canSendLinks,
        canSendMessages,
        slowModeSeconds,
        lastMessageAt,
        restrictedBy,
        createdAt,
        updatedAt,
      ];

  MemberRestriction copyWith({
    String? groupId,
    String? nodeId,
    bool? isMuted,
    DateTime? mutedUntil,
    bool? canSendMedia,
    bool? canSendLinks,
    bool? canSendMessages,
    int? slowModeSeconds,
    DateTime? lastMessageAt,
    String? restrictedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MemberRestriction(
      groupId: groupId ?? this.groupId,
      nodeId: nodeId ?? this.nodeId,
      isMuted: isMuted ?? this.isMuted,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      canSendMedia: canSendMedia ?? this.canSendMedia,
      canSendLinks: canSendLinks ?? this.canSendLinks,
      canSendMessages: canSendMessages ?? this.canSendMessages,
      slowModeSeconds: slowModeSeconds ?? this.slowModeSeconds,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      restrictedBy: restrictedBy ?? this.restrictedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
