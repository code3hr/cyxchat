import 'dart:typed_data';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/identity.dart';
import '../utils/node_id_utils.dart';
import 'database_service.dart';

/// Instance ID for running multiple test instances
const String _instanceId = String.fromEnvironment('INSTANCE_ID', defaultValue: '');

/// Service for managing user identity
class IdentityService {
  static final IdentityService instance = IdentityService._();

  final _secureStorage = const FlutterSecureStorage();

  /// Get instance-specific key for secure storage
  String _storageKey(String key) => _instanceId.isEmpty ? key : '${key}_$_instanceId';
  Identity? _currentIdentity;

  IdentityService._();

  /// Initialize the service
  Future<void> initialize() async {
    await _loadIdentity();
  }

  /// Get current identity
  Identity? get currentIdentity => _currentIdentity;

  /// Check if identity exists
  bool get hasIdentity => _currentIdentity != null;

  /// Load identity from database
  Future<void> _loadIdentity() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('identity', limit: 1);

    if (rows.isNotEmpty) {
      _currentIdentity = Identity.fromMap(rows.first);
    }
  }

  /// Create new identity
  Future<Identity> createIdentity({String? displayName}) async {
    final db = await DatabaseService.instance.database;

    // Generate node ID as UUID v4 (cryptographically secure random)
    final nodeId = NodeIdUtils.generate();

    // Generate key pair using secure random (placeholder - real implementation uses libcyxchat)
    final random = Random.secure();
    final publicKey = Uint8List(32);
    final privateKey = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      publicKey[i] = random.nextInt(256);
      privateKey[i] = random.nextInt(256);
    }

    // Store private key securely
    await _secureStorage.write(
      key: _storageKey('private_key'),
      value: String.fromCharCodes(privateKey),
    );

    // Create identity
    final identity = Identity(
      nodeId: nodeId,
      displayName: displayName,
      publicKey: publicKey,
      createdAt: DateTime.now(),
    );

    // Save to database
    await db.insert('identity', {
      ...identity.toMap(),
      'private_key_encrypted': String.fromCharCodes(privateKey),
    });

    _currentIdentity = identity;
    return identity;
  }

  /// Update display name
  Future<void> updateDisplayName(String? name) async {
    if (_currentIdentity == null) return;

    final db = await DatabaseService.instance.database;
    await db.update(
      'identity',
      {'display_name': name},
      where: 'node_id = ?',
      whereArgs: [_currentIdentity!.nodeId],
    );

    _currentIdentity = _currentIdentity!.copyWith(displayName: name);
  }

  /// Get private key (for signing/encryption)
  Future<Uint8List?> getPrivateKey() async {
    final keyStr = await _secureStorage.read(key: _storageKey('private_key'));
    if (keyStr == null) return null;
    return Uint8List.fromList(keyStr.codeUnits);
  }

  /// Delete identity (logout/reset)
  Future<void> deleteIdentity() async {
    await _secureStorage.delete(key: _storageKey('private_key'));
    await DatabaseService.instance.clearAllData();
    _currentIdentity = null;
  }

  /// Generate QR code data for sharing identity
  String generateQrData() {
    if (_currentIdentity == null) return '';

    final pubkeyHex = _currentIdentity!.publicKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return 'cyxchat://add/${_currentIdentity!.nodeId}/$pubkeyHex';
  }
}
