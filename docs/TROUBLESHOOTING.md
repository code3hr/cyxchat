# CyxChat Troubleshooting Guide

This document covers common issues and platform-specific problems when building and running CyxChat.

## Table of Contents

- [Platform-Specific Issues](#platform-specific-issues)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Linux](#linux)
- [Build Issues](#build-issues)
- [Network & Connectivity](#network--connectivity)
- [App Runtime Issues](#app-runtime-issues)

---

## Platform-Specific Issues

### macOS

#### Error 42018: errSecNotAvailable (Keychain Access Denied)

**Symptoms:**
- App crashes on startup or when creating/loading identity
- Error message: `PlatformException(Error 42018, The operation couldn't be completed...)`
- Full error: `com.apple.security.keychain errSecNotAvailable`

**Cause:**
Error 42018 (`errSecNotAvailable`) is a macOS keychain error that occurs when the app tries to access the system keychain but doesn't have permission due to app sandbox restrictions. This happens when using `flutter_secure_storage` on macOS in debug mode or when the app isn't properly code-signed.

**Solution (Already Implemented):**
CyxChat automatically detects macOS and uses `SharedPreferences` instead of the system keychain to store sensitive data like private keys. This workaround is implemented in `app/lib/services/identity_service.dart`:

```dart
// Lines 36-66 in identity_service.dart
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
```

**Security Note:**
The private keys are currently stored **unencrypted** in:
```
~/Library/Containers/com.example.cyxchat/Data/Library/Preferences/
```

This location is only accessible to the current user due to macOS sandbox protections. However, this is **NOT recommended for production** because:
- Keys are stored in plaintext (not encrypted)
- Any process running as the same user could potentially read them
- If an attacker gains user-level access, keys are exposed

**Current Protection:**
- macOS file system permissions (restricted to the app)
- Application sandbox (prevents other apps from accessing the data)
- Disk encryption if FileVault is enabled (encrypts data at rest)

**For Production Releases:**

See the [Production Security Fix Guide](#production-fix-macos-keychain-security) below for complete implementation steps.

**Verification:**
Check your entitlements file at `app/macos/Runner/Release.entitlements` to ensure it includes:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.cyxchat.app</string>
</array>
```

---

#### Build Fails: libsodium not found

**Symptoms:**
```
CMake Error: Could not find libsodium
```

**Solution:**
```bash
# Install via Homebrew
brew install libsodium

# If CMake still can't find it, set the path explicitly:
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DSODIUM_INCLUDE_DIR=/opt/homebrew/include \
  -DSODIUM_LIBRARY=/opt/homebrew/lib/libsodium.dylib
```

---

### Windows

#### DLL not found

**Symptoms:**
```
Error: cyxchat.dll not found
```

**Solution:**
1. Build the C library first:
   ```powershell
   cd lib
   cmake -B build -DCMAKE_BUILD_TYPE=Release
   cmake --build build --config Release
   ```

2. Copy DLL to app directory:
   ```powershell
   copy lib\build\Release\cyxchat.dll app\
   ```

3. Alternatively, add to PATH:
   ```powershell
   $env:PATH += ";$PWD\lib\build\Release"
   ```

---

#### vcpkg libsodium installation fails

**Symptoms:**
```
Error: Failed to build libsodium
```

**Solution:**
```powershell
# Use x64 triplet explicitly
vcpkg install libsodium:x64-windows

# Update vcpkg itself
cd vcpkg
git pull
.\bootstrap-vcpkg.bat
```

---

### Linux

#### libsodium.so not found at runtime

**Symptoms:**
```
error while loading shared libraries: libsodium.so.23: cannot open shared object file
```

**Solution:**
```bash
# Update library cache
sudo ldconfig

# Or set LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Verify installation
ldconfig -p | grep sodium
```

---

#### Permission denied: UDP socket

**Symptoms:**
```
Error: Permission denied (binding UDP socket)
```

**Solution:**
```bash
# If using port < 1024, either:
# 1. Run with elevated permissions (not recommended)
# 2. Use a port >= 1024 (recommended)

# Allow binding to low ports without root (Linux only)
sudo setcap 'cap_net_bind_service=+ep' ./build/cyxwizd
```

---

## Build Issues

### CMake version too old

**Symptoms:**
```
CMake Error: CMake 3.16 or higher is required
```

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-add-repository ppa:ubuntu-toolchain-r/test
sudo apt update
sudo apt install cmake

# macOS
brew upgrade cmake

# Windows
# Download from https://cmake.org/download/
```

---

### Flutter SDK not found

**Symptoms:**
```
'flutter' is not recognized as an internal or external command
```

**Solution:**
```bash
# Verify Flutter installation
flutter doctor

# Add to PATH if needed
# Linux/macOS: Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:/path/to/flutter/bin"

# Windows: Add to System Environment Variables
```

---

## Network & Connectivity

### Bootstrap connection failed

**Symptoms:**
- App shows "Disconnected" in Network Status
- No peers discovered
- Messages stuck in "Pending" state

**Diagnosis:**
1. Verify bootstrap server is running:
   ```bash
   # From conspiracy root
   ./build/cyxwizd
   # In daemon prompt:
   /bootstrap 7777
   ```

2. Check if port is open:
   ```bash
   # Linux/macOS
   nc -zvu 127.0.0.1 7777

   # Windows
   Test-NetConnection -ComputerName 127.0.0.1 -Port 7777
   ```

3. Verify firewall allows UDP traffic on port 7777

**Solution:**
- Ensure bootstrap address in app matches server: Settings → Network → Bootstrap Server
- Default: `127.0.0.1:7777` for local testing
- For remote server: Use public IP or domain, e.g., `your-server.com:7777`

---

### Peer not found / Messages not sending

**Symptoms:**
- Contact added but shows offline permanently
- Messages stuck at "Sent" (✓) and never reach "Delivered" (✓✓)

**Diagnosis:**
1. Both peers must use the **same bootstrap server**
2. Check logs for key exchange completion
3. NAT traversal may take 5-10 seconds

**Solution:**
```bash
# Enable verbose logging
flutter run --verbose

# Look for:
# - "STUN discovery successful"
# - "Registered with bootstrap"
# - "Key exchange complete with peer"
```

---

### NAT traversal failing

**Symptoms:**
- Peers registered but can't connect directly
- All messages go through relay (slow)

**Diagnosis:**
Check NAT type:
```bash
# In cyxwizd daemon
/stun check
```

**Solution:**
- **Symmetric NAT**: Direct connections may fail, relay fallback will be used
- **Port-restricted NAT**: Usually works with hole punching
- **Full Cone NAT**: Always works

For persistent issues:
1. Try enabling UPnP on your router
2. Manually forward UDP port in router settings
3. Use relay fallback (automatic, but slower)

---

## App Runtime Issues

### Database migration errors

**Symptoms:**
```
DatabaseException: no such table: conversations
```

**Solution:**
```bash
# Delete old database (WARNING: loses all data)
# Linux/macOS
rm -rf ~/.local/share/cyxchat/

# Windows
rmdir /s %APPDATA%\cyxchat\

# Then restart app to recreate fresh database
```

---

### Multiple instances conflict

**Symptoms:**
- Running two test instances overwrites each other's data

**Solution:**
Use `INSTANCE_ID` environment variable:
```bash
# Terminal 1
flutter run -d windows

# Terminal 2
flutter run -d windows --dart-define=INSTANCE_ID=2

# Terminal 3
flutter run -d windows --dart-define=INSTANCE_ID=3
```

Each instance gets its own:
- Identity (Node ID)
- Database
- Secure storage keys

---

### Voice messages fail to record

**Symptoms:**
- Microphone button doesn't work
- "Permission denied" error

**Solution:**
1. Grant microphone permissions:
   - **macOS**: System Preferences → Security & Privacy → Microphone
   - **Windows**: Settings → Privacy → Microphone
   - **Linux**: Check PulseAudio/PipeWire permissions

2. Verify `record` plugin is properly installed:
   ```bash
   cd app
   flutter pub get
   ```

---

### File transfer fails immediately

**Symptoms:**
- File attachment shows "Failed" without sending any chunks
- Files over 64KB don't send

**Diagnosis:**
Check transfer mode in Settings → Privacy → Fast File Transfer

**Solution:**
- **Onion mode** (default): Max 64KB, anonymous
  - For larger files, enable Direct Mode

- **Direct mode**: Max 4GB, but exposes IP address
  - Requires both sender and receiver to enable it
  - Trades privacy for speed

---

### App crashes on startup

**Symptoms:**
- App window opens briefly then closes
- No error message visible

**Diagnosis:**
Check logs:
```bash
# Run with verbose logging
flutter run -d windows --verbose

# Or check system logs
# macOS: Console.app
# Windows: Event Viewer
# Linux: journalctl or ~/.local/share/cyxchat/logs/
```

**Common causes:**
1. Missing native library (cyxchat.dll/.so/.dylib)
2. Incompatible library version
3. Corrupted database
4. Keychain access issues (see macOS section above)

**Solution:**
1. Rebuild native library
2. Clear app data
3. Check platform-specific issues above

---

## Production Fix: macOS Keychain Security

This guide shows how to properly secure private keys on macOS for production redistribution.

### Overview

The current implementation uses SharedPreferences (plaintext storage) to avoid keychain errors during development. For production, you have two options:

**Option 1: Proper Keychain Integration (Recommended)**
- Use macOS Keychain Services with proper code signing
- Most secure, follows Apple best practices
- Requires Apple Developer account ($99/year)

**Option 2: Encrypted SharedPreferences (Interim)**
- Encrypt keys before storing in SharedPreferences
- No code signing required
- Less secure than Keychain, but better than plaintext

---

### Option 1: Proper Keychain Integration (Recommended)

This is the recommended approach for production apps distributed via App Store or DMG.

#### Step 1: Obtain Apple Developer Certificate

1. Enroll in [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
2. In Xcode, go to **Preferences → Accounts → Manage Certificates**
3. Create a **Developer ID Application** certificate (for distribution outside App Store) or **Mac App Distribution** certificate (for App Store)

#### Step 2: Update Entitlements

Edit `app/macos/Runner/DebugProfile.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <!-- ADD THIS FOR KEYCHAIN ACCESS -->
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.cyxchat.app</string>
    </array>
</dict>
</plist>
```

Also update `app/macos/Runner/Release.entitlements` with the same keychain-access-groups entry.

#### Step 3: Configure Code Signing

Edit `app/macos/Runner.xcodeproj/project.pbxproj` or configure in Xcode:

1. Open `app/macos/Runner.xcworkspace` in Xcode
2. Select **Runner** project → **Signing & Capabilities**
3. Enable **Automatically manage signing**
4. Select your **Team** (from Apple Developer account)
5. Ensure **Signing Certificate** shows your Developer ID

Or manually edit `project.pbxproj` to add:
```
CODE_SIGN_IDENTITY = "Developer ID Application: Your Name (TEAM_ID)";
CODE_SIGN_STYLE = Manual;
DEVELOPMENT_TEAM = YOUR_TEAM_ID;
```

#### Step 4: Update identity_service.dart

Replace the platform check to use keychain on properly signed macOS builds:

```dart
import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdentityService {
  // ... existing code ...

  /// Check if we should use keychain or SharedPreferences
  bool get _shouldUseKeychain {
    if (!Platform.isMacOS) return true; // Other platforms always use secure storage

    // On macOS, check if we're properly code signed
    // In production builds, this will be true; in debug, false
    return const bool.fromEnvironment('USE_KEYCHAIN', defaultValue: false);
  }

  /// Write secure data
  Future<void> _writeSecure(String key, String value) async {
    if (_shouldUseKeychain) {
      // Use flutter_secure_storage (Keychain on macOS)
      await _secureStorage.write(key: _storageKey(key), value: value);
    } else {
      // Development fallback: use SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey(key), value);
    }
  }

  /// Read secure data
  Future<String?> _readSecure(String key) async {
    if (_shouldUseKeychain) {
      return await _secureStorage.read(key: _storageKey(key));
    } else {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_storageKey(key));
    }
  }

  /// Delete secure data
  Future<void> _deleteSecure(String key) async {
    if (_shouldUseKeychain) {
      await _secureStorage.delete(key: _storageKey(key));
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey(key));
    }
  }
}
```

#### Step 5: Build with Keychain Enabled

For production builds, compile with the USE_KEYCHAIN flag:

```bash
# Production build
flutter build macos --release --dart-define=USE_KEYCHAIN=true

# The app will now use Keychain Services
# Development builds (without flag) will continue using SharedPreferences
```

#### Step 6: Code Sign the Built App

```bash
# Navigate to build output
cd build/macos/Build/Products/Release

# Sign the app bundle
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  CyxChat.app

# Verify signature
codesign --verify --deep --strict --verbose=2 CyxChat.app
spctl --assess --type execute --verbose=4 CyxChat.app
```

#### Step 7: Create Distributable Package

**For App Store:**
```bash
# Archive in Xcode, then upload via App Store Connect
# Xcode → Product → Archive → Distribute App → App Store Connect
```

**For Direct Distribution (DMG):**
```bash
# Create DMG
hdiutil create -volname "CyxChat" -srcfolder CyxChat.app -ov -format UDZO CyxChat.dmg

# Sign the DMG
codesign --sign "Developer ID Application: Your Name (TEAM_ID)" CyxChat.dmg

# Notarize with Apple (required for macOS 10.15+)
xcrun notarytool submit CyxChat.dmg --apple-id your@email.com --password <app-specific-password> --team-id TEAM_ID

# Staple the notarization ticket
xcrun stapler staple CyxChat.dmg
```

---

### Option 2: Encrypted SharedPreferences (Interim)

If you can't obtain an Apple Developer certificate immediately, you can encrypt keys before storing them in SharedPreferences.

#### Step 1: Add Dependencies

Add to `app/pubspec.yaml`:
```yaml
dependencies:
  encrypt: ^5.0.3
  device_info_plus: ^9.1.1
```

#### Step 2: Create Encryption Helper

Create `app/lib/services/macos_secure_storage.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted storage for macOS using device-specific encryption
class MacOSSecureStorage {
  static encrypt.Key? _encryptionKey;
  static final _iv = encrypt.IV.fromLength(16);

  /// Get device-specific encryption key
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

    _encryptionKey = encrypt.Key(keyHash.bytes as Uint8List);
    return _encryptionKey!;
  }

  /// Write encrypted data
  static Future<void> write(String key, String value) async {
    final encryptionKey = await _getEncryptionKey();
    final encrypter = encrypt.Encrypter(encrypt.AES(encryptionKey));

    // Encrypt the value
    final encrypted = encrypter.encrypt(value, iv: _iv);

    // Store encrypted value
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, encrypted.base64);
  }

  /// Read encrypted data
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
      print('Failed to decrypt key $key: $e');
      return null;
    }
  }

  /// Delete encrypted data
  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
```

#### Step 3: Update identity_service.dart

Replace the macOS-specific code:

```dart
import 'package:cyxchat/services/macos_secure_storage.dart' if (dart.library.io) 'package:cyxchat/services/macos_secure_storage.dart';

class IdentityService {
  // ... existing code ...

  /// Write secure data (encrypted on macOS, secure storage elsewhere)
  Future<void> _writeSecure(String key, String value) async {
    if (Platform.isMacOS) {
      // Use encrypted SharedPreferences on macOS
      await MacOSSecureStorage.write(_storageKey(key), value);
    } else {
      await _secureStorage.write(key: _storageKey(key), value: value);
    }
  }

  /// Read secure data
  Future<String?> _readSecure(String key) async {
    if (Platform.isMacOS) {
      return await MacOSSecureStorage.read(_storageKey(key));
    } else {
      return await _secureStorage.read(key: _storageKey(key));
    }
  }

  /// Delete secure data
  Future<void> _deleteSecure(String key) async {
    if (Platform.isMacOS) {
      await MacOSSecureStorage.delete(_storageKey(key));
    } else {
      await _secureStorage.delete(key: _storageKey(key));
    }
  }
}
```

#### Step 4: Test Encrypted Storage

```bash
# Rebuild and test
cd app
flutter pub get
flutter run -d macos

# Verify keys are encrypted:
cat ~/Library/Containers/com.example.cyxchat/Data/Library/Preferences/com.example.cyxchat.plist
# Should see encrypted base64 strings instead of plaintext
```

#### Security Notes for Option 2

**Strengths:**
- Keys are encrypted at rest
- Device-specific encryption (key bound to hardware UUID)
- No plaintext storage
- Works without code signing

**Limitations:**
- Encryption key is derived from hardware UUID (accessible to any process running as the user)
- Still vulnerable if attacker has user-level access to the running app
- Not as secure as Keychain with Secure Enclave
- Encryption key stored in memory during app runtime

**Recommendation:**
Use Option 2 as an **interim solution** only. Migrate to Option 1 (proper Keychain) for production releases distributed to end users.

---

### Migration Path

If you have existing users on the plaintext version:

```dart
class IdentityService {
  Future<void> _migrateToSecureStorage() async {
    if (!Platform.isMacOS) return;

    // Check if migration is needed
    final prefs = await SharedPreferences.getInstance();
    final plaintextKey = prefs.getString('private_key');

    if (plaintextKey != null) {
      print('Migrating private key to secure storage...');

      // Write to new secure storage
      await _writeSecure('private_key', plaintextKey);

      // Remove plaintext version
      await prefs.remove('private_key');

      print('Migration complete');
    }
  }

  Future<void> initialize() async {
    await _migrateToSecureStorage();
    await _loadIdentity();
  }
}
```

---

### Verification Checklist

Before releasing to production:

- [ ] Code signing certificate obtained and installed
- [ ] Entitlements configured with keychain-access-groups
- [ ] identity_service.dart updated to use Keychain
- [ ] App successfully builds with code signing
- [ ] Keychain access tested on clean macOS install
- [ ] App notarized by Apple (for macOS 10.15+)
- [ ] DMG/installer code signed
- [ ] Migration from old storage tested (if applicable)
- [ ] Private keys verified in macOS Keychain (Keychain Access.app)
- [ ] Error 42018 no longer occurs

---

## Getting Help

If your issue isn't covered here:

1. **Check logs**: Run with `flutter run --verbose` and look for errors
2. **Search issues**: https://github.com/code3hr/conspiracy/issues
3. **Create issue**: Include:
   - Platform (OS + version)
   - Flutter version (`flutter --version`)
   - CMake version (`cmake --version`)
   - Error logs
   - Steps to reproduce

---

## Related Documentation

- [README.md](../README.md) - Quick start guide
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System design
- [NAT-TRAVERSAL.md](./NAT-TRAVERSAL.md) - Connection details
- [CYXCHAT.md](./CYXCHAT.md) - Full protocol specification
