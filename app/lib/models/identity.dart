import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Local user identity
class Identity extends Equatable {
  /// 32-byte node ID (hex encoded)
  final String nodeId;

  /// Display name (optional)
  final String? displayName;

  /// X25519 public key (32 bytes)
  final Uint8List publicKey;

  /// Creation timestamp
  final DateTime createdAt;

  const Identity({
    required this.nodeId,
    this.displayName,
    required this.publicKey,
    required this.createdAt,
  });

  /// Create from database row
  factory Identity.fromMap(Map<String, dynamic> map) {
    return Identity(
      nodeId: map['node_id'] as String,
      displayName: map['display_name'] as String?,
      publicKey: Uint8List.fromList(
        (map['public_key'] as String).codeUnits,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
      ),
    );
  }

  /// Convert to database row
  Map<String, dynamic> toMap() {
    return {
      'node_id': nodeId,
      'display_name': displayName,
      'public_key': String.fromCharCodes(publicKey),
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  /// Short node ID for display (first 8 chars)
  String get shortId => nodeId.length >= 8 ? nodeId.substring(0, 8) : nodeId;

  /// Display name or short ID
  String get displayText => displayName ?? shortId;

  @override
  List<Object?> get props => [nodeId, displayName, publicKey, createdAt];

  Identity copyWith({
    String? nodeId,
    String? displayName,
    Uint8List? publicKey,
    DateTime? createdAt,
  }) {
    return Identity(
      nodeId: nodeId ?? this.nodeId,
      displayName: displayName ?? this.displayName,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
