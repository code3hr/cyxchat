import 'package:equatable/equatable.dart';

/// Constants matching C library CYXCHAT_INVITE_LINK_* constants
class InviteLinkConstants {
  static const int idSize = 16; // 16 bytes = 32 hex chars
  static const int maxLinksPerGroup = 20;
  static const int maxNameLength = 64;
  static const int defaultExpiryMs = 604800000; // 7 days
  static const int maxExpiryMs = 2592000000; // 30 days
}

/// Group invite link for sharing join URLs
class InviteLink extends Equatable {
  final String id;
  final String groupId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int? maxUses;
  final int useCount;
  final bool isRevoked;
  final String? name;

  const InviteLink({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.createdAt,
    this.expiresAt,
    this.maxUses,
    this.useCount = 0,
    this.isRevoked = false,
    this.name,
  });

  factory InviteLink.fromMap(Map<String, dynamic> map) {
    return InviteLink(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      expiresAt: map['expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expires_at'] as int)
          : null,
      maxUses: map['max_uses'] as int?,
      useCount: (map['use_count'] as int?) ?? 0,
      isRevoked: (map['is_revoked'] as int?) == 1,
      name: map['link_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'created_by': createdBy,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'max_uses': maxUses,
      'use_count': useCount,
      'is_revoked': isRevoked ? 1 : 0,
      'link_name': name,
    };
  }

  /// Check if link is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Check if link has reached max uses
  bool get isMaxedOut {
    if (maxUses == null || maxUses == 0) return false;
    return useCount >= maxUses!;
  }

  /// Check if link is still valid (not expired, not revoked, not maxed out)
  bool get isValid => !isRevoked && !isExpired && !isMaxedOut;

  /// Get remaining uses (null if unlimited)
  int? get remainingUses {
    if (maxUses == null || maxUses == 0) return null;
    return maxUses! - useCount;
  }

  /// Get time until expiry (null if never expires)
  Duration? get timeUntilExpiry {
    if (expiresAt == null) return null;
    final now = DateTime.now();
    if (now.isAfter(expiresAt!)) return Duration.zero;
    return expiresAt!.difference(now);
  }

  /// Generate the share URL for this invite link
  String toUrl() {
    // Format: cyxchat://join/<group_id_hex>/<link_id_hex>
    return 'cyxchat://join/$groupId/$id';
  }

  /// Parse group ID and link ID from URL
  /// Returns null if URL is invalid
  static ({String groupId, String linkId})? parseUrl(String url) {
    // Supported formats:
    // cyxchat://join/<group_id>/<link_id>
    // https://cyxchat.app/join/<group_id>/<link_id>
    final patterns = [
      RegExp(r'^cyxchat://join/([a-fA-F0-9]+)/([a-fA-F0-9]+)$'),
      RegExp(r'^https?://cyxchat\.app/join/([a-fA-F0-9]+)/([a-fA-F0-9]+)$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return (groupId: match.group(1)!, linkId: match.group(2)!);
      }
    }
    return null;
  }

  /// Get human-readable status
  String get statusText {
    if (isRevoked) return 'Revoked';
    if (isExpired) return 'Expired';
    if (isMaxedOut) return 'Max uses reached';
    return 'Active';
  }

  /// Get expiry description
  String get expiryText {
    if (expiresAt == null) return 'Never expires';
    if (isExpired) return 'Expired';

    final remaining = timeUntilExpiry!;
    if (remaining.inDays > 0) {
      return 'Expires in ${remaining.inDays} day${remaining.inDays > 1 ? 's' : ''}';
    }
    if (remaining.inHours > 0) {
      return 'Expires in ${remaining.inHours} hour${remaining.inHours > 1 ? 's' : ''}';
    }
    if (remaining.inMinutes > 0) {
      return 'Expires in ${remaining.inMinutes} minute${remaining.inMinutes > 1 ? 's' : ''}';
    }
    return 'Expires soon';
  }

  /// Get uses description
  String get usesText {
    if (maxUses == null || maxUses == 0) return 'Unlimited uses';
    return '$useCount / $maxUses uses';
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        createdBy,
        createdAt,
        expiresAt,
        maxUses,
        useCount,
        isRevoked,
        name,
      ];

  InviteLink copyWith({
    String? id,
    String? groupId,
    String? createdBy,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? maxUses,
    int? useCount,
    bool? isRevoked,
    String? name,
  }) {
    return InviteLink(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      maxUses: maxUses ?? this.maxUses,
      useCount: useCount ?? this.useCount,
      isRevoked: isRevoked ?? this.isRevoked,
      name: name ?? this.name,
    );
  }
}

/// Record of who joined via which invite link
class InviteLinkUsage extends Equatable {
  final String linkId;
  final String nodeId;
  final DateTime joinedAt;

  const InviteLinkUsage({
    required this.linkId,
    required this.nodeId,
    required this.joinedAt,
  });

  factory InviteLinkUsage.fromMap(Map<String, dynamic> map) {
    return InviteLinkUsage(
      linkId: map['link_id'] as String,
      nodeId: map['node_id'] as String,
      joinedAt: DateTime.fromMillisecondsSinceEpoch(map['joined_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'link_id': linkId,
      'node_id': nodeId,
      'joined_at': joinedAt.millisecondsSinceEpoch,
    };
  }

  @override
  List<Object?> get props => [linkId, nodeId, joinedAt];
}
