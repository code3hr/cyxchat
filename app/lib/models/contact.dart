import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Contact presence status
enum PresenceStatus {
  offline,
  online,
  away,
  busy,
  invisible;

  String get displayName {
    switch (this) {
      case PresenceStatus.offline:
        return 'Offline';
      case PresenceStatus.online:
        return 'Online';
      case PresenceStatus.away:
        return 'Away';
      case PresenceStatus.busy:
        return 'Busy';
      case PresenceStatus.invisible:
        return 'Invisible';
    }
  }

  static PresenceStatus fromInt(int value) {
    if (value >= 0 && value < PresenceStatus.values.length) {
      return PresenceStatus.values[value];
    }
    return PresenceStatus.offline;
  }
}

/// Contact entry
class Contact extends Equatable {
  final String nodeId;
  final Uint8List publicKey;
  final String? displayName;
  final bool verified;
  final bool blocked;
  final DateTime addedAt;
  final DateTime? lastSeen;
  final PresenceStatus presence;
  final String? statusText;

  const Contact({
    required this.nodeId,
    required this.publicKey,
    this.displayName,
    this.verified = false,
    this.blocked = false,
    required this.addedAt,
    this.lastSeen,
    this.presence = PresenceStatus.offline,
    this.statusText,
  });

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      nodeId: map['node_id'] as String,
      publicKey: Uint8List.fromList(
        (map['public_key'] as String).codeUnits,
      ),
      displayName: map['display_name'] as String?,
      verified: (map['verified'] as int?) == 1,
      blocked: (map['blocked'] as int?) == 1,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
      lastSeen: map['last_seen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_seen'] as int)
          : null,
      presence: PresenceStatus.fromInt(map['presence'] as int? ?? 0),
      statusText: map['status_text'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'node_id': nodeId,
      'public_key': String.fromCharCodes(publicKey),
      'display_name': displayName,
      'verified': verified ? 1 : 0,
      'blocked': blocked ? 1 : 0,
      'added_at': addedAt.millisecondsSinceEpoch,
      'last_seen': lastSeen?.millisecondsSinceEpoch,
      'presence': presence.index,
      'status_text': statusText,
    };
  }

  String get shortId => nodeId.length >= 8 ? nodeId.substring(0, 8) : nodeId;

  String get displayText => displayName ?? shortId;

  bool get isOnline =>
      presence != PresenceStatus.offline &&
      presence != PresenceStatus.invisible;

  @override
  List<Object?> get props => [
        nodeId,
        publicKey,
        displayName,
        verified,
        blocked,
        addedAt,
        lastSeen,
        presence,
        statusText,
      ];

  Contact copyWith({
    String? nodeId,
    Uint8List? publicKey,
    String? displayName,
    bool? verified,
    bool? blocked,
    DateTime? addedAt,
    DateTime? lastSeen,
    PresenceStatus? presence,
    String? statusText,
  }) {
    return Contact(
      nodeId: nodeId ?? this.nodeId,
      publicKey: publicKey ?? this.publicKey,
      displayName: displayName ?? this.displayName,
      verified: verified ?? this.verified,
      blocked: blocked ?? this.blocked,
      addedAt: addedAt ?? this.addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      presence: presence ?? this.presence,
      statusText: statusText ?? this.statusText,
    );
  }
}
