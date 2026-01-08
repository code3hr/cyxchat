import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../utils/node_id_utils.dart';

/// Local user identity
class Identity extends Equatable {
  /// Node ID (UUID format: "550e8400-e29b-41d4-a716-446655440000")
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

  /// Short node ID for display (first segment of UUID or first 8 chars)
  String get shortId => NodeIdUtils.shortId(nodeId);

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
