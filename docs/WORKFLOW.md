# CyxChat Development Workflow

## Overview

This document outlines the development workflow for building CyxChat during the hackathon. Follow these steps to set up, develop, test, and debug the application.

---

## Quick Start

### Initial Setup (One-time)

```bash
# 1. Clone and enter project
cd D:\Dev\conspiracy\cyxchat

# 2. Build C library (libcyxchat)
cd lib
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
cd ..

# 3. Set up Flutter app
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run ffigen
cd ..

# 4. Verify setup
cd app
flutter doctor
flutter run
```

---

## Project Layout

```
cyxchat/
├── lib/                    # C Library (libcyxchat)
│   ├── include/cyxchat/    # Headers
│   ├── src/                # Implementation
│   ├── tests/              # C unit tests
│   └── build/              # Build output
│
├── app/                    # Flutter Application
│   ├── lib/                # Dart source
│   ├── test/               # Dart tests
│   └── [platforms]/        # Platform folders
│
└── docs/                   # Documentation
```

---

## Development Cycle

### Typical Development Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Development Cycle                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────┐                                                      │
│   │ Write Code   │                                                      │
│   └──────┬───────┘                                                      │
│          │                                                               │
│          ▼                                                               │
│   ┌──────────────┐     ┌──────────────┐                                │
│   │ C Code?      │────►│ Build C lib  │                                │
│   └──────┬───────┘ Yes └──────┬───────┘                                │
│          │ No                 │                                         │
│          │                    ▼                                         │
│          │            ┌──────────────┐                                  │
│          │            │ Run C tests  │                                  │
│          │            └──────┬───────┘                                  │
│          │                   │                                          │
│          │                   ▼                                          │
│          │            ┌──────────────┐                                  │
│          │            │ FFI changed? │                                  │
│          │            └──────┬───────┘                                  │
│          │                   │ Yes                                      │
│          │                   ▼                                          │
│          │            ┌──────────────┐                                  │
│          │            │ Run ffigen   │                                  │
│          │            └──────┬───────┘                                  │
│          │                   │                                          │
│          ▼                   ▼                                          │
│   ┌──────────────────────────────────┐                                 │
│   │         Hot Reload / Restart      │                                 │
│   └──────────────┬───────────────────┘                                 │
│                  │                                                      │
│                  ▼                                                      │
│   ┌──────────────────────────────────┐                                 │
│   │         Test in App              │                                 │
│   └──────────────┬───────────────────┘                                 │
│                  │                                                      │
│                  ▼                                                      │
│   ┌──────────────────────────────────┐                                 │
│   │         Run Tests                │                                 │
│   └──────────────┬───────────────────┘                                 │
│                  │                                                      │
│                  ▼                                                      │
│   ┌──────────────────────────────────┐                                 │
│   │         Commit                   │                                 │
│   └──────────────────────────────────┘                                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Terminal Setup

### Recommended: 4 Terminal Windows

```
┌─────────────────────────────────┬─────────────────────────────────┐
│  Terminal 1: C Build            │  Terminal 2: Flutter Run        │
│  ─────────────────────          │  ────────────────────           │
│  cd cyxchat/lib                 │  cd cyxchat/app                 │
│  cmake --build build            │  flutter run -d windows         │
│                                 │                                 │
│  (rebuild after C changes)      │  (hot reload: r, restart: R)    │
├─────────────────────────────────┼─────────────────────────────────┤
│  Terminal 3: Tests              │  Terminal 4: Code Gen           │
│  ─────────────────              │  ───────────────                │
│  cd cyxchat/app                 │  cd cyxchat/app                 │
│  flutter test                   │  dart run build_runner watch    │
│                                 │                                 │
│  (run tests on demand)          │  (auto-gen freezed, riverpod)   │
└─────────────────────────────────┴─────────────────────────────────┘
```

---

## Working with C Code

### Building the C Library

```bash
# Navigate to C library
cd cyxchat/lib

# Configure (first time or after CMakeLists changes)
cmake -B build -DCMAKE_BUILD_TYPE=Debug

# Build
cmake --build build

# Run tests
ctest --test-dir build --output-on-failure

# Clean and rebuild
cmake --build build --clean-first
```

### After C API Changes

When you modify C headers (`include/cyxchat/*.h`):

```bash
# 1. Rebuild C library
cd cyxchat/lib
cmake --build build

# 2. Regenerate FFI bindings
cd ../app
dart run ffigen

# 3. Hot restart Flutter (press 'R' in flutter run)
```

### C Debugging

```bash
# Build with debug symbols
cmake -B build -DCMAKE_BUILD_TYPE=Debug

# Windows: Use Visual Studio debugger
# Open build/cyxchat.sln

# Linux/macOS: Use GDB/LLDB
gdb ./build/test_chat
lldb ./build/test_chat

# Add debug logging
export CYXCHAT_LOG_LEVEL=debug
```

---

## Working with Flutter

### Running the App

```bash
cd cyxchat/app

# List available devices
flutter devices

# Run on specific device
flutter run -d windows    # Windows desktop
flutter run -d macos      # macOS desktop
flutter run -d linux      # Linux desktop
flutter run -d chrome     # Web (limited, no FFI)
flutter run -d <device>   # Mobile device/emulator

# Run in release mode
flutter run --release

# Run with verbose output
flutter run -v
```

### Hot Reload vs Hot Restart

| Action | Shortcut | When to Use |
|--------|----------|-------------|
| Hot Reload | `r` | UI changes, stateless widget changes |
| Hot Restart | `R` | State changes, provider changes, FFI changes |
| Full Restart | `q` then `flutter run` | Native code changes, plugin changes |

### Code Generation

```bash
cd cyxchat/app

# One-time generation
dart run build_runner build --delete-conflicting-outputs

# Watch mode (auto-regenerate on file changes)
dart run build_runner watch --delete-conflicting-outputs

# Clean generated files
dart run build_runner clean
```

### FFI Bindings Generation

```bash
cd cyxchat/app

# Generate bindings from C headers
dart run ffigen

# Check ffigen.yaml for configuration
```

---

## Testing

### C Tests

```bash
cd cyxchat/lib

# Run all tests
ctest --test-dir build --output-on-failure

# Run specific test
./build/test_chat

# Run with verbose output
ctest --test-dir build -V

# Run specific test by name
ctest --test-dir build -R "test_send_message"
```

### Flutter Tests

```bash
cd cyxchat/app

# Run all tests
flutter test

# Run specific test file
flutter test test/unit/chat_service_test.dart

# Run with coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html

# Run integration tests
flutter test integration_test

# Run tests in watch mode (third-party)
# Install: dart pub global activate test_cov
test_cov --watch
```

### Test Structure

```
app/test/
├── unit/                    # Unit tests
│   ├── models/              # Model tests
│   ├── services/            # Service tests
│   └── providers/           # Provider tests
├── widget/                  # Widget tests
│   ├── screens/             # Screen tests
│   └── components/          # Component tests
└── integration/             # Integration tests
    └── app_test.dart
```

### Writing Tests

```dart
// Unit test example
import 'package:flutter_test/flutter_test.dart';
import 'package:cyxchat/core/models/message.dart';

void main() {
  group('Message', () {
    test('should create from database row', () {
      final row = {
        'id': 1,
        'conversation_id': 1,
        'msg_id': Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        'sender_id': Uint8List(32),
        'type': 0x10,
        'content_text': 'Hello',
        'status': 0,
        'created_at': 1234567890,
      };

      final message = Message.fromDb(row);

      expect(message.id, 1);
      expect(message.contentText, 'Hello');
    });
  });
}

// Widget test example
import 'package:flutter_test/flutter_test.dart';
import 'package:cyxchat/features/chat/widgets/message_bubble.dart';

void main() {
  testWidgets('MessageBubble shows text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessageBubble(
          text: 'Hello',
          isMe: true,
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
  });
}
```

---

## Debugging

### Flutter Debugging

```bash
# Run with DevTools
flutter run --observatory-port=8888
# Open http://localhost:8888 in browser

# Debug print
debugPrint('Message: $message');

# Riverpod debugging
class MyObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    debugPrint('Provider ${provider.name}: $previousValue -> $newValue');
  }
}
```

### FFI Debugging

```dart
// Check library loading
try {
  final lib = DynamicLibrary.open('cyxchat.dll');
  print('Library loaded successfully');
} catch (e) {
  print('Failed to load library: $e');
}

// Debug FFI calls
print('Calling cyxchat_create...');
final result = _bindings.cyxchat_create(...);
print('Result: $result');
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Library not found | Check DLL/so/dylib is in correct path |
| Symbol not found | Rebuild C library, regenerate FFI bindings |
| Segfault in FFI | Check pointer handling, memory allocation |
| Hot reload not working | Use hot restart (R) for FFI changes |
| Code gen errors | Run `build_runner build --delete-conflicting-outputs` |
| SQLite errors | Check schema, run migrations |

---

## Git Workflow

### Branch Strategy

```
main                    # Stable, production-ready
├── develop             # Integration branch
│   ├── feature/chat    # Feature branches
│   ├── feature/groups
│   └── fix/message-status
```

### Commit Messages

```bash
# Format: <type>(<scope>): <description>

# Types
feat:     New feature
fix:      Bug fix
docs:     Documentation
style:    Formatting
refactor: Code restructure
test:     Tests
chore:    Maintenance

# Examples
git commit -m "feat(chat): add message sending"
git commit -m "fix(ffi): handle null pointer in callback"
git commit -m "docs(database): add schema documentation"
```

### Daily Workflow

```bash
# Start of day
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feature/my-feature

# Work, commit frequently
git add .
git commit -m "feat(chat): implement send message"

# End of day
git push origin feature/my-feature

# When feature is done
git checkout develop
git merge feature/my-feature
git push origin develop
```

---

## Build for Release

### Windows

```bash
cd cyxchat/app
flutter build windows --release

# Output: build/windows/x64/runner/Release/
```

### macOS

```bash
cd cyxchat/app
flutter build macos --release

# Output: build/macos/Build/Products/Release/CyxChat.app
```

### Linux

```bash
cd cyxchat/app
flutter build linux --release

# Output: build/linux/x64/release/bundle/
```

### Android

```bash
cd cyxchat/app

# APK
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release

# Output: build/app/outputs/
```

### iOS

```bash
cd cyxchat/app

# Build
flutter build ios --release

# Archive in Xcode for App Store
```

---

## Performance Tips

### During Development

1. **Use Debug builds for C** - Faster iteration
2. **Use hot reload** - Faster than hot restart
3. **Watch mode for code gen** - Auto-regenerate
4. **Limit test scope** - Run specific tests

### For Release

1. **Release mode for C** - Optimized binary
2. **Profile mode for testing** - `flutter run --profile`
3. **Analyze bundle size** - `flutter build --analyze-size`

---

## Hackathon Tips

### Priority Order

```
Day 1:
├── Project setup (Flutter + C library)
├── FFI bridge working
├── Basic UI scaffold
└── Database schema

Day 2:
├── Identity creation
├── Contact management
├── Basic messaging (send/receive)
└── Local storage working

Day 3:
├── Conversation list
├── Chat screen
├── Message status
└── Polish UI

Day 4:
├── Group chat
├── File sharing
├── Testing
└── Bug fixes

Day 5:
├── Final testing
├── Performance optimization
├── Documentation
└── Demo preparation
```

### Shortcuts for Speed

```dart
// Use extensions for common operations
extension DateTimeX on DateTime {
  String get timeAgo => // ...
}

// Use constants file
class K {
  static const maxMessageLength = 1000;
  static const messageRetryDelay = Duration(seconds: 5);
}

// Use snippets (VS Code)
// Create snippets for common patterns
```

### When Stuck

1. **Check logs** - `flutter run -v`
2. **Check FFI** - Is library loaded? Bindings correct?
3. **Check database** - Schema correct? Migrations run?
4. **Simplify** - Comment out code, isolate issue
5. **Ask teammate** - Fresh eyes help

---

## Quick Reference Commands

```bash
# ===== C Library =====
cd cyxchat/lib
cmake -B build                        # Configure
cmake --build build                   # Build
ctest --test-dir build               # Test

# ===== Flutter =====
cd cyxchat/app
flutter pub get                       # Get dependencies
flutter run                           # Run app
flutter test                          # Run tests
dart run build_runner build          # Code generation
dart run ffigen                       # FFI generation

# ===== Shortcuts =====
r                                     # Hot reload (in flutter run)
R                                     # Hot restart (in flutter run)
q                                     # Quit (in flutter run)
```

---

## Checklist: Before Demo

- [ ] App runs without crashes
- [ ] Can create identity
- [ ] Can add contacts
- [ ] Can send/receive messages
- [ ] Messages persist after restart
- [ ] UI is presentable
- [ ] No obvious bugs in demo flow
- [ ] Backup demo data prepared
