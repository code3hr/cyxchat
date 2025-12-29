# CyxChat Quick Start

## Prerequisites

- CMake 3.16+
- C compiler (GCC, Clang, or MSVC)
- libsodium
- Flutter 3.10+
- Dart 3.0+

## Setup

### Windows (PowerShell)
```powershell
cd cyxchat/scripts
.\dev.ps1 setup
```

### Linux/macOS
```bash
cd cyxchat/scripts
chmod +x *.sh
./dev.sh setup
```

## Development Commands

| Command | Windows | Linux/macOS |
|---------|---------|-------------|
| Build C library | `.\dev.ps1 lib` | `./dev.sh lib` |
| Run Flutter app | `.\dev.ps1 app` | `./dev.sh app` |
| Run all tests | `.\dev.ps1 test` | `./dev.sh test` |
| Clean builds | `.\dev.ps1 clean` | `./dev.sh clean` |

## Project Structure

```
cyxchat/
├── lib/                    # C library (libcyxchat)
│   ├── include/cyxchat/    # Public headers
│   ├── src/                # Source files
│   ├── tests/              # Unit tests
│   └── CMakeLists.txt      # Build config
│
├── app/                    # Flutter app
│   ├── lib/
│   │   ├── main.dart       # Entry point
│   │   ├── models/         # Data models
│   │   ├── services/       # Business logic
│   │   ├── providers/      # State management
│   │   ├── screens/        # UI screens
│   │   ├── widgets/        # Reusable widgets
│   │   └── ffi/            # C library bindings
│   └── pubspec.yaml
│
├── scripts/                # Build scripts
├── docs/                   # Documentation
└── CYXCHAT.md             # Design document
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │ Screens  │ │ Widgets  │ │Providers │ │ Services │  │
│  └──────────┘ └──────────┘ └──────────┘ └────┬─────┘  │
│                                               │        │
│                                         ┌─────▼─────┐  │
│                                         │    FFI    │  │
│                                         └─────┬─────┘  │
└─────────────────────────────────────────────────┼──────┘
                                                  │
┌─────────────────────────────────────────────────┼──────┐
│                    libcyxchat                   │      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────▼───┐  │
│  │   Chat   │ │ Contact  │ │  Group   │ │ Presence │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
└────────────────────────────┬───────────────────────────┘
                             │
┌────────────────────────────▼───────────────────────────┐
│                    libcyxwiz                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │  Onion   │ │ Routing  │ │  Crypto  │ │Transport │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
└────────────────────────────────────────────────────────┘
```

## Key Files

### C Library Headers
- `types.h` - Message types, error codes, constants
- `chat.h` - Direct messaging API
- `contact.h` - Contact management
- `group.h` - Group chat API
- `file.h` - File transfer API
- `presence.h` - Online status API

### Flutter Screens
- `onboarding_screen.dart` - First-time setup
- `home_screen.dart` - Conversation list
- `chat_screen.dart` - Chat view
- `contacts_screen.dart` - Contact list
- `settings_screen.dart` - App settings

## Next Steps

1. **Implement FFI bridge** - Connect Flutter to C library
2. **Add contact provider** - Manage contacts in state
3. **Integrate onion routing** - Connect to libcyxwiz
4. **Add QR scanner** - Use mobile_scanner package
5. **Implement file transfer** - Large file handling

## Documentation

- `CYXCHAT.md` - Full design specification
- `docs/DATABASE.md` - SQLite schema
- `docs/WORKFLOW.md` - Development workflow
- `docs/C_EXTENSION.md` - C library details
- `docs/API.md` - Flutter API reference
