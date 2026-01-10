import 'dart:typed_data';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/identity.dart';
import '../utils/node_id_utils.dart';
import 'database_service.dart';
import 'macos_secure_storage.dart';

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
  ///
  /// This performs:
  /// 1. Migration from plaintext to encrypted storage (macOS only, automatic)
  /// 2. Loading identity from database
  Future<void> initialize() async {
    // Migrate from plaintext to encrypted storage (macOS only)
    await _migrateToEncryptedStorage();

    // Load identity
    await _loadIdentity();
  }

  /// Get current identity
  Identity? get currentIdentity => _currentIdentity;

  /// Check if identity exists
  bool get hasIdentity => _currentIdentity != null;

  /// Write secure data (uses encrypted storage on macOS, secure storage elsewhere)
  ///
  /// macOS Implementation:
  /// - Uses AES-256 encryption with hardware UUID-based key
  /// - Keys stored encrypted in SharedPreferences
  /// - Better than plaintext, but not as secure as Keychain
  /// - Avoids Error 42018 (errSecNotAvailable - keychain access denied)
  ///
  /// Storage location (macOS):
  /// ~/Library/Containers/com.example.cyxchat/Data/Library/Preferences/
  ///
  /// For production releases requiring maximum security:
  /// 1. Obtain Apple Developer code signing certificate ($99/year)
  /// 2. Add keychain entitlements to macos/Runner/Release.entitlements
  /// 3. Migrate to proper Keychain integration (see docs/PRODUCTION-MACOS.md)
  ///
  /// See docs/PRODUCTION-MACOS.md for migration guide.
  Future<void> _writeSecure(String key, String value) async {
    if (Platform.isMacOS) {
      // On macOS, use encrypted SharedPreferences to avoid keychain issues
      // while still providing encryption at rest
      await MacOSSecureStorage.write(_storageKey(key), value);
    } else {
      await _secureStorage.write(key: _storageKey(key), value: value);
    }
  }

  /// Read secure data (uses encrypted storage on macOS)
  ///
  /// Returns null if:
  /// - Key doesn't exist
  /// - Decryption fails (on macOS)
  ///
  /// See _writeSecure() for implementation details.
  Future<String?> _readSecure(String key) async {
    if (Platform.isMacOS) {
      return await MacOSSecureStorage.read(_storageKey(key));
    } else {
      return await _secureStorage.read(key: _storageKey(key));
    }
  }

  /// Delete secure data (uses encrypted storage on macOS)
  ///
  /// See _writeSecure() for implementation details.
  Future<void> _deleteSecure(String key) async {
    if (Platform.isMacOS) {
      await MacOSSecureStorage.delete(_storageKey(key));
    } else {
      await _secureStorage.delete(key: _storageKey(key));
    }
  }

  /// Migrate from plaintext SharedPreferences to encrypted storage (macOS only)
  ///
  /// This function automatically migrates existing plaintext private keys
  /// to encrypted storage. It runs on every app startup to catch any
  /// users upgrading from the old version.
  ///
  /// Migration process:
  /// 1. Check if plaintext key exists in SharedPreferences
  /// 2. If found, encrypt it using MacOSSecureStorage
  /// 3. Delete the plaintext version
  /// 4. Mark migration as complete
  Future<void> _migrateToEncryptedStorage() async {
    if (!Platform.isMacOS) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final plaintextKey = prefs.getString(_storageKey('private_key'));

      if (plaintextKey != null) {
        print('[IdentityService] Migrating private key to encrypted storage...');

        // Write to encrypted storage
        await MacOSSecureStorage.write(_storageKey('private_key'), plaintextKey);

        // Verify encrypted storage worked
        final verifyRead = await MacOSSecureStorage.read(_storageKey('private_key'));
        if (verifyRead == plaintextKey) {
          // Remove plaintext version only after successful encryption
          await prefs.remove(_storageKey('private_key'));
          print('[IdentityService] Migration complete - private key now encrypted');
        } else {
          print('[IdentityService] ERROR: Migration verification failed - keeping plaintext for safety');
        }
      }
    } catch (e) {
      print('[IdentityService] ERROR during migration: $e');
      // Don't remove plaintext key if migration failed
    }
  }

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

    // Store private key securely (uses SharedPreferences on macOS)
    await _writeSecure('private_key', String.fromCharCodes(privateKey));

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
    final keyStr = await _readSecure('private_key');
    if (keyStr == null) return null;
    return Uint8List.fromList(keyStr.codeUnits);
  }

  /// Delete identity (logout/reset)
  Future<void> deleteIdentity() async {
    await _deleteSecure('private_key');
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
