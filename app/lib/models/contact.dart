import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../utils/node_id_utils.dart';

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
    // public_key is stored as BLOB, sqflite returns it as Uint8List
    final pubkeyData = map['public_key'];
    Uint8List publicKey;
    if (pubkeyData is Uint8List) {
      publicKey = pubkeyData;
    } else if (pubkeyData is List<int>) {
      publicKey = Uint8List.fromList(pubkeyData);
    } else if (pubkeyData is String) {
      // Legacy data: might be stored as raw character codes or hex
      // If string length is 32, it's likely raw bytes stored via String.fromCharCodes
      // If string length is 64, it's likely hex
      if (pubkeyData.length == 32) {
        publicKey = Uint8List.fromList(pubkeyData.codeUnits);
      } else if (pubkeyData.length >= 64) {
        // Try hex parsing
        try {
          final cleanHex = pubkeyData.replaceAll('-', '');
          final bytes = <int>[];
          for (int i = 0; i < cleanHex.length && bytes.length < 32; i += 2) {
            bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
          }
          publicKey = Uint8List.fromList(bytes);
        } catch (e) {
          // If hex parsing fails, use codeUnits
          publicKey = Uint8List.fromList(pubkeyData.codeUnits.take(32).toList());
        }
      } else {
        // Unknown format, use codeUnits (truncated/padded to 32)
        final codes = pubkeyData.codeUnits;
        final padded = List<int>.filled(32, 0);
        for (int i = 0; i < codes.length && i < 32; i++) {
          padded[i] = codes[i];
        }
        publicKey = Uint8List.fromList(padded);
      }
    } else {
      publicKey = Uint8List(32); // Empty key as fallback
    }

    return Contact(
      nodeId: map['node_id'] as String,
      publicKey: publicKey,
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
      'public_key': publicKey, // Stored as BLOB directly
      'display_name': displayName,
      'verified': verified ? 1 : 0,
      'blocked': blocked ? 1 : 0,
      'added_at': addedAt.millisecondsSinceEpoch,
      'last_seen': lastSeen?.millisecondsSinceEpoch,
      'presence': presence.index,
      'status_text': statusText,
    };
  }

  String get shortId => NodeIdUtils.shortId(nodeId);

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
