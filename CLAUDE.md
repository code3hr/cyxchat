# CyxChat CLAUDE.md

This file provides guidance to Claude Code when working with the CyxChat codebase.

## Project Overview

CyxChat is a decentralized, privacy-first messaging application built on the CyxWiz protocol.

**Vision**: "WhatsApp + Gmail without servers"
- No central servers - all peer-to-peer
- Works from any location (behind NAT, firewalls, mobile networks)
- End-to-end encrypted
- Local storage (your data stays on your device)
- Cross-platform (mobile + desktop)

## CRITICAL: Do Not Modify Core CyxWiz

**NEVER modify files in the core CyxWiz protocol directory (`../../include/cyxwiz/` or `../../src/`).**

The CyxWiz protocol is used by multiple processes and applications. Any changes to core CyxWiz files will affect all dependent projects.

When implementing CyxChat-specific features:
- Add new message types to `cyxchat/lib/include/cyxchat/types.h` (not `cyxwiz/types.h`)
- Clone/adapt CyxWiz patterns into CyxChat's own codebase
- Use CyxWiz APIs as-is; don't extend them in the core library
- Define CyxChat-specific constants with `CYXCHAT_` prefix

Example - DNS message types are defined in CyxChat, not CyxWiz:
```c
/* In cyxchat/lib/include/cyxchat/types.h */
#define CYXCHAT_MSG_DNS_REGISTER      0xD0
#define CYXCHAT_MSG_DNS_LOOKUP        0xD2
/* NOT in cyxwiz/types.h */
```

## Architecture

```
┌─────────────────────────────────────────┐
│          Flutter App (Dart)             │
│  • UI screens (chat, contacts, etc.)    │
│  • Providers (state management)         │
│  • Services (database, identity)        │
├─────────────────────────────────────────┤
│          FFI Bindings (Dart→C)          │
│  • app/lib/ffi/bindings.dart            │
├─────────────────────────────────────────┤
│          libcyxchat (C library)         │
│  • Chat, Contact, Group, File, Presence │
│  • Connection management (NAT traversal)│
│  • Relay fallback                       │
├─────────────────────────────────────────┤
│          libcyxwiz (Core Protocol)      │
│  • Transport (UDP, WiFi Direct, BT, LoRa│
│  • Onion routing (anonymous messaging)  │
│  • Crypto (X25519, XChaCha20-Poly1305)  │
└─────────────────────────────────────────┘
```

## Project Structure

```
cyxchat/
├── lib/                    # C library (libcyxchat)
│   ├── include/cyxchat/    # Public headers
│   │   ├── cyxchat.h       # Main header (includes all)
│   │   ├── types.h         # Types, constants, error codes
│   │   ├── chat.h          # Direct messaging API
│   │   ├── contact.h       # Contact management
│   │   ├── group.h         # Group chat
│   │   ├── file.h          # File transfer
│   │   ├── presence.h      # Online status
│   │   ├── connection.h    # NAT traversal/connection mgmt
│   │   ├── relay.h         # Relay fallback
│   │   └── dns.h           # Internal DNS (usernames)
│   ├── src/                # Implementation
│   │   ├── cyxchat.c       # Library init/shutdown
│   │   ├── chat.c          # Messaging implementation
│   │   ├── contact.c       # Contact implementation
│   │   ├── group.c         # Group implementation
│   │   ├── file.c          # File transfer implementation
│   │   ├── presence.c      # Presence implementation
│   │   ├── connection.c    # Connection management
│   │   ├── relay.c         # Relay implementation
│   │   └── dns.c           # DNS implementation (gossip-based)
│   ├── tests/              # Unit tests
│   └── CMakeLists.txt      # Build configuration
│
├── app/                    # Flutter application
│   ├── lib/
│   │   ├── main.dart       # App entry point
│   │   ├── ffi/
│   │   │   └── bindings.dart   # FFI bindings to libcyxchat
│   │   ├── models/         # Data models
│   │   │   ├── identity.dart
│   │   │   ├── contact.dart
│   │   │   ├── message.dart
│   │   │   └── conversation.dart
│   │   ├── services/       # Business logic
│   │   │   ├── database_service.dart
│   │   │   ├── identity_service.dart
│   │   │   └── chat_service.dart
│   │   ├── providers/      # State management
│   │   │   ├── identity_provider.dart
│   │   │   ├── conversation_provider.dart
│   │   │   └── dns_provider.dart
│   │   └── screens/        # UI screens
│   │       ├── home_screen.dart
│   │       ├── chat_screen.dart
│   │       ├── contacts_screen.dart
│   │       └── settings_screen.dart
│   └── pubspec.yaml
│
└── docs/                   # Documentation
    ├── README.md           # Overview
    ├── ARCHITECTURE.md     # System design
    ├── NAT-TRAVERSAL.md    # UDP hole punching
    ├── DNS.md              # Internal naming
    ├── LABELS.md           # MPLS-style routing
    ├── EMAIL.md            # CyxMail protocol
    └── GATEWAY.md          # Email gateway
```

## Build Commands

### C Library (libcyxchat)

```bash
# From cyxchat/lib directory

# Configure
cmake -B build -DCMAKE_BUILD_TYPE=Debug

# Build
cmake --build build

# Run tests
ctest --test-dir build
```

### Flutter App

```bash
# From cyxchat/app directory

# Get dependencies
flutter pub get

# Run on desktop (requires libcyxchat.dll/.so/.dylib in path)
flutter run -d windows   # or linux, macos

# Build release
flutter build windows    # or linux, macos, apk, ios
```

### Full Build (Library + App)

```bash
# Build C library first
cd cyxchat/lib
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release

# Copy library to Flutter app
# Windows: copy build/Release/cyxchat.dll ../app/
# Linux:   cp build/libcyxchat.so ../app/
# macOS:   cp build/libcyxchat.dylib ../app/

# Build Flutter app
cd ../app
flutter build windows  # or appropriate platform
```

## Key Integration Points

### CyxWiz Integration

CyxChat depends on libcyxwiz for:
- **Transport** (`cyxwiz/transport.h`) - UDP with STUN/hole punching
- **Peer Management** (`cyxwiz/peer.h`) - Peer table and discovery
- **Router** (`cyxwiz/routing.h`) - Multi-hop routing
- **Onion Routing** (`cyxwiz/onion.h`) - Anonymous messaging

The integration hierarchy:
```
cyxchat_ctx_t
    └── cyxwiz_onion_ctx_t
            └── cyxwiz_router_t
                    └── cyxwiz_transport_t (UDP)
                            └── STUN, hole punch, bootstrap
```

### Connection Flow

1. **STUN Discovery** - Discover public IP:port
2. **Bootstrap Register** - Register with bootstrap server
3. **Peer Discovery** - Learn about other peers
4. **Hole Punch** - Direct P2P connection attempt
5. **Relay Fallback** - If hole punch fails, use relay

## Error Codes

```c
CYXCHAT_OK              =  0   // Success
CYXCHAT_ERR_NULL        = -1   // Null pointer
CYXCHAT_ERR_MEMORY      = -2   // Memory allocation failed
CYXCHAT_ERR_INVALID     = -3   // Invalid parameter
CYXCHAT_ERR_NOT_FOUND   = -4   // Item not found
CYXCHAT_ERR_EXISTS      = -5   // Already exists
CYXCHAT_ERR_FULL        = -6   // Container full
CYXCHAT_ERR_CRYPTO      = -7   // Crypto operation failed
CYXCHAT_ERR_NETWORK     = -8   // Network error
CYXCHAT_ERR_TIMEOUT     = -9   // Operation timeout
CYXCHAT_ERR_BLOCKED     = -10  // User is blocked
```

## Message Types

| Range | Category | Examples |
|-------|----------|----------|
| 0x10-0x1F | Direct Messages | TEXT, ACK, READ, TYPING |
| 0x20-0x2F | Group Messages | GROUP_TEXT, INVITE, JOIN, LEAVE |
| 0x30-0x3F | Presence | PRESENCE, PRESENCE_REQ |
| 0xD0-0xD9 | DNS (Internal) | DNS_REGISTER, DNS_LOOKUP, DNS_RESPONSE |

## FFI Patterns

When adding new C functions:

1. **Header** - Add declaration in `include/cyxchat/*.h`
2. **Implementation** - Add in `src/*.c`
3. **FFI Binding** - Add in `app/lib/ffi/bindings.dart`:
   ```dart
   // In CyxChatBindings class
   int myFunction(args) => _native.cyxchat_my_function(args);

   // In CyxChatNative class
   late final cyxchat_my_function = _lib.lookupFunction<
       NativeReturnType Function(NativeArgs),
       DartReturnType Function(DartArgs)>('cyxchat_my_function');
   ```

## Dependencies

- **libcyxwiz** - Core protocol (parent project at `../../`)
- **libsodium** - Cryptography
- **Flutter** - Mobile/desktop UI framework
- **SQLite** - Local storage (via sqflite package)

## Testing

```bash
# C library tests
cd cyxchat/lib
ctest --test-dir build --output-on-failure

# Flutter tests
cd cyxchat/app
flutter test
```

## Related Documentation

- [../CLAUDE.md](../CLAUDE.md) - Main CyxWiz protocol documentation
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - CyxChat architecture
- [docs/NAT-TRAVERSAL.md](docs/NAT-TRAVERSAL.md) - NAT traversal details
