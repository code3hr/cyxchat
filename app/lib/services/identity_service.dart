import 'dart:typed_data';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Write secure data (uses SharedPreferences on macOS to avoid keychain issues)
  ///
  /// SECURITY WARNING (macOS):
  /// Private keys are stored UNENCRYPTED in SharedPreferences at:
  /// ~/Library/Containers/com.example.cyxchat/Data/Library/Preferences/
  ///
  /// This workaround avoids Error 42018 (errSecNotAvailable) during development,
  /// but is NOT suitable for production. For production releases:
  /// 1. Obtain Apple Developer code signing certificate
  /// 2. Add keychain entitlements to macos/Runner/Release.entitlements
  /// 3. Remove this macOS workaround to use Keychain Services
  ///
  /// See docs/TROUBLESHOOTING.md for details.
  Future<void> _writeSecure(String key, String value) async {
    if (Platform.isMacOS) {
      // On macOS, use SharedPreferences instead of secure storage
      // to avoid keychain access issues with app sandbox
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey(key), value);
    } else {
      await _secureStorage.write(key: _storageKey(key), value: value);
    }
  }

  /// Read secure data (uses SharedPreferences on macOS to avoid keychain issues)
  ///
  /// See _writeSecure() for security warnings.
  Future<String?> _readSecure(String key) async {
    if (Platform.isMacOS) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_storageKey(key));
    } else {
      return await _secureStorage.read(key: _storageKey(key));
    }
  }

  /// Delete secure data (uses SharedPreferences on macOS to avoid keychain issues)
  ///
  /// See _writeSecure() for security warnings.
  Future<void> _deleteSecure(String key) async {
    if (Platform.isMacOS) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey(key));
    } else {
      await _secureStorage.delete(key: _storageKey(key));
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
