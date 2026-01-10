import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted storage for macOS using device-specific encryption
///
/// This class provides encrypted storage for private keys on macOS to avoid
/// Error 42018 (errSecNotAvailable - keychain access denied) while still
/// providing better security than plaintext storage.
///
/// **Security Model:**
/// - Encryption key derived from hardware UUID + app-specific salt
/// - AES-256 encryption in CBC mode
/// - Keys are encrypted at rest
/// - Device-specific (can't be moved to another Mac)
///
/// **Limitations:**
/// - Encryption key accessible to any process running as the same user
/// - Not as secure as macOS Keychain with Secure Enclave
/// - Should be replaced with proper Keychain integration for production
///
/// See docs/PRODUCTION-MACOS.md for migration guide to proper Keychain.
class MacOSSecureStorage {
  static encrypt.Key? _encryptionKey;
  static final _iv = encrypt.IV.fromLength(16);

  /// Get device-specific encryption key
  ///
  /// The encryption key is derived from:
  /// 1. macOS hardware UUID (unique per Mac)
  /// 2. App-specific salt
  /// 3. SHA-256 hashing
  ///
  /// This ensures keys are bound to the specific hardware and cannot be
  /// easily moved to another machine.
  static Future<encrypt.Key> _getEncryptionKey() async {
    if (_encryptionKey != null) return _encryptionKey!;

    // Get hardware UUID (unique per Mac)
    final deviceInfo = DeviceInfoPlugin();
    final macInfo = await deviceInfo.macOsInfo();
    final hardwareUUID = macInfo.systemGUID ?? 'fallback-uuid';

    // Derive encryption key from hardware UUID + app-specific salt
    const appSalt = 'cyxchat-macos-encryption-v1';
    final keyMaterial = '$hardwareUUID:$appSalt';
    final keyHash = sha256.convert(utf8.encode(keyMaterial));

    // Use SHA-256 hash as AES key (32 bytes)
    _encryptionKey = encrypt.Key(Uint8List.fromList(keyHash.bytes));
    return _encryptionKey!;
  }

  /// Write encrypted data to SharedPreferences
  ///
  /// The value is encrypted with AES-256 before being stored.
  ///
  /// Example:
  /// ```dart
  /// await MacOSSecureStorage.write('private_key', keyData);
  /// ```
  static Future<void> write(String key, String value) async {
    final encryptionKey = await _getEncryptionKey();
    final encrypter = encrypt.Encrypter(encrypt.AES(encryptionKey));

    // Encrypt the value
    final encrypted = encrypter.encrypt(value, iv: _iv);

    // Store encrypted value as base64
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, encrypted.base64);
  }

  /// Read encrypted data from SharedPreferences
  ///
  /// The value is decrypted after retrieval.
  ///
  /// Returns null if:
  /// - Key doesn't exist
  /// - Decryption fails (corrupted data or wrong encryption key)
  ///
  /// Example:
  /// ```dart
  /// final key = await MacOSSecureStorage.read('private_key');
  /// if (key == null) {
  ///   print('Key not found or decryption failed');
  /// }
  /// ```
  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedValue = prefs.getString(key);

    if (encryptedValue == null) return null;

    try {
      final encryptionKey = await _getEncryptionKey();
      final encrypter = encrypt.Encrypter(encrypt.AES(encryptionKey));

      // Decrypt the value
      final decrypted = encrypter.decrypt64(encryptedValue, iv: _iv);
      return decrypted;
    } catch (e) {
      // Decryption failed - data may be corrupted or encryption key changed
      print('[MacOSSecureStorage] Failed to decrypt key "$key": $e');
      return null;
    }
  }

  /// Delete encrypted data from SharedPreferences
  ///
  /// Example:
  /// ```dart
  /// await MacOSSecureStorage.delete('private_key');
  /// ```
  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Check if a key exists in storage
  ///
  /// Example:
  /// ```dart
  /// if (await MacOSSecureStorage.containsKey('private_key')) {
  ///   print('Private key exists');
  /// }
  /// ```
  static Future<bool> containsKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key);
  }

  /// Clear all encrypted data
  ///
  /// WARNING: This will delete all stored keys permanently.
  ///
  /// Example:
  /// ```dart
  /// await MacOSSecureStorage.clear();
  /// ```
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
