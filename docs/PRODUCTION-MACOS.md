# macOS Production Release Guide

Quick reference for preparing CyxChat for macOS production distribution.

## Current Issue

**Private keys are stored unencrypted** in:
```
~/Library/Containers/com.example.cyxchat/Data/Library/Preferences/
```

This is acceptable for development but **NOT for production**.

## Choose Your Approach

### Option 1: Proper Keychain (Recommended) ⭐

**Requirements:**
- Apple Developer account ($99/year)
- Code signing certificate
- Keychain entitlements

**Security Level:** ⭐⭐⭐⭐⭐ (Highest - uses macOS Keychain with Secure Enclave)

**Best for:**
- App Store distribution
- Direct distribution (DMG)
- Production releases to end users

**Time to implement:** ~2-3 hours (including Apple Developer setup)

[Full Implementation Guide →](TROUBLESHOOTING.md#option-1-proper-keychain-integration-recommended)

---

### Option 2: Encrypted SharedPreferences (Interim)

**Requirements:**
- No code signing needed
- Add encryption dependencies

**Security Level:** ⭐⭐⭐ (Better than plaintext, but not as secure as Keychain)

**Best for:**
- Internal testing/staging builds
- Beta releases to trusted users
- Temporary solution while obtaining Apple Developer certificate

**Time to implement:** ~1 hour

[Full Implementation Guide →](TROUBLESHOOTING.md#option-2-encrypted-sharedpreferences-interim)

---

## Quick Start: Option 1 (Keychain)

### 1. Setup (One-time)

```bash
# Enroll in Apple Developer Program
# https://developer.apple.com/programs/

# Open Xcode and add your account
# Xcode → Preferences → Accounts → Add (+)

# Create certificate
# Xcode → Preferences → Accounts → Manage Certificates → Create
# Choose: "Developer ID Application" (for DMG) or "Mac App Distribution" (for App Store)
```

### 2. Update Entitlements

Edit `app/macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<!-- Add this inside <dict> tag -->
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.cyxchat.app</string>
</array>
```

### 3. Update Code

Replace `app/lib/services/identity_service.dart` methods:

```dart
// Add this property
bool get _shouldUseKeychain {
  if (!Platform.isMacOS) return true;
  return const bool.fromEnvironment('USE_KEYCHAIN', defaultValue: false);
}

// Update _writeSecure, _readSecure, _deleteSecure to check _shouldUseKeychain
// See full code in troubleshooting guide
```

### 4. Configure Code Signing

```bash
# Open in Xcode
cd app/macos
open Runner.xcworkspace

# In Xcode:
# 1. Select "Runner" project
# 2. Go to "Signing & Capabilities"
# 3. Enable "Automatically manage signing"
# 4. Select your Team
```

### 5. Build

```bash
cd app
flutter build macos --release --dart-define=USE_KEYCHAIN=true
```

### 6. Sign & Notarize

```bash
cd build/macos/Build/Products/Release

# Sign the app
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  CyxChat.app

# Create DMG
hdiutil create -volname "CyxChat" -srcfolder CyxChat.app -ov -format UDZO CyxChat.dmg

# Sign DMG
codesign --sign "Developer ID Application: Your Name (TEAM_ID)" CyxChat.dmg

# Notarize (macOS 10.15+)
xcrun notarytool submit CyxChat.dmg \
  --apple-id your@email.com \
  --password <app-specific-password> \
  --team-id TEAM_ID

# Staple notarization
xcrun stapler staple CyxChat.dmg
```

### 7. Verify

```bash
# Check signature
codesign --verify --deep --strict --verbose=2 CyxChat.app

# Check notarization
spctl --assess --type execute --verbose=4 CyxChat.app

# Install and test on clean Mac
# Keys should now be in Keychain (check Keychain Access.app)
```

---

## Quick Start: Option 2 (Encrypted Storage)

### 1. Add Dependencies

```bash
cd app
flutter pub add encrypt device_info_plus
```

### 2. Create Encryption Helper

Create `app/lib/services/macos_secure_storage.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MacOSSecureStorage {
  static encrypt.Key? _encryptionKey;
  static final _iv = encrypt.IV.fromLength(16);

  static Future<encrypt.Key> _getEncryptionKey() async {
    if (_encryptionKey != null) return _encryptionKey!;

    final deviceInfo = DeviceInfoPlugin();
    final macInfo = await deviceInfo.macOsInfo();
    final hardwareUUID = macInfo.systemGUID ?? 'fallback-uuid';

    const appSalt = 'cyxchat-macos-encryption-v1';
    final keyMaterial = '$hardwareUUID:$appSalt';
    final keyHash = sha256.convert(utf8.encode(keyMaterial));

    _encryptionKey = encrypt.Key(Uint8List.fromList(keyHash.bytes));
    return _encryptionKey!;
  }

  static Future<void> write(String key, String value) async {
    final encryptionKey = await _getEncryptionKey();
    final encrypter = encrypt.Encrypter(encrypt.AES(encryptionKey));
    final encrypted = encrypter.encrypt(value, iv: _iv);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, encrypted.base64);
  }

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedValue = prefs.getString(key);
    if (encryptedValue == null) return null;

    try {
      final encryptionKey = await _getEncryptionKey();
      final encrypter = encrypt.Encrypter(encrypt.AES(encryptionKey));
      return encrypter.decrypt64(encryptedValue, iv: _iv);
    } catch (e) {
      return null;
    }
  }

  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
```

### 3. Update identity_service.dart

```dart
import 'package:cyxchat/services/macos_secure_storage.dart';

class IdentityService {
  // Update methods:
  Future<void> _writeSecure(String key, String value) async {
    if (Platform.isMacOS) {
      await MacOSSecureStorage.write(_storageKey(key), value);
    } else {
      await _secureStorage.write(key: _storageKey(key), value: value);
    }
  }

  // Similar updates for _readSecure and _deleteSecure
}
```

### 4. Test

```bash
flutter run -d macos

# Verify encryption:
cat ~/Library/Containers/com.example.cyxchat/Data/Library/Preferences/com.example.cyxchat.plist
# Should see encrypted base64 strings, not plaintext
```

---

## Production Checklist

Before releasing to users:

### Security
- [ ] Private keys no longer in plaintext
- [ ] Encryption verified (Option 1 or 2 implemented)
- [ ] App properly code signed (Option 1 only)
- [ ] Notarization complete (Option 1, macOS 10.15+)

### Testing
- [ ] Fresh install test on clean macOS
- [ ] Identity creation works
- [ ] Keys accessible after restart
- [ ] No Error 42018 occurs
- [ ] Migration from old version tested (if applicable)

### Distribution
- [ ] DMG created and signed
- [ ] Installer tested
- [ ] Update documentation with new security features
- [ ] Release notes mention security improvements

---

## Migration for Existing Users

If you have users on the old plaintext version:

```dart
// Add to IdentityService
Future<void> _migrateToSecureStorage() async {
  if (!Platform.isMacOS) return;

  final prefs = await SharedPreferences.getInstance();
  final plaintextKey = prefs.getString('private_key');

  if (plaintextKey != null) {
    print('Migrating private key to secure storage...');
    await _writeSecure('private_key', plaintextKey);
    await prefs.remove('private_key'); // Remove plaintext
    print('Migration complete');
  }
}

Future<void> initialize() async {
  await _migrateToSecureStorage();
  await _loadIdentity();
}
```

---

## Comparison

| Feature | Current (Dev) | Option 1 (Keychain) | Option 2 (Encrypted) |
|---------|---------------|---------------------|----------------------|
| **Storage** | Plaintext | Keychain | Encrypted file |
| **Security** | ⚠️ Low | ✅ Highest | ✓ Better |
| **Code Signing** | Not required | Required | Not required |
| **Apple Developer** | Not needed | Required ($99/yr) | Not needed |
| **Secure Enclave** | No | Yes | No |
| **Setup Time** | - | 2-3 hours | 1 hour |
| **Production Ready** | ❌ No | ✅ Yes | ⚠️ Interim only |

---

## Troubleshooting

### "Code signing failed"
- Verify certificate is installed: `security find-identity -v -p codesigning`
- Check team ID matches in Xcode

### "Keychain access denied" after implementing Option 1
- Verify entitlements are included in build
- Check `--dart-define=USE_KEYCHAIN=true` flag used
- Ensure app is properly code signed

### "Encryption key not found" with Option 2
- Check `device_info_plus` permissions
- Verify macOS system UUID is accessible

---

## Support

- Full guide: [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- GitHub issues: https://github.com/code3hr/conspiracy/issues
- Security concerns: Use GitHub security advisories

---

**Remember:** Option 1 (Keychain) is STRONGLY RECOMMENDED for any production release to end users. Option 2 is only suitable as an interim solution.
