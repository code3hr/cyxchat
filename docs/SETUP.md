# CyxChat Development Setup Guide

## Overview

This document covers everything needed to set up the CyxChat development environment, from project structure to platform-specific build requirements.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Technology Stack](#technology-stack)
3. [C Extensions (libcyxchat)](#c-extensions-libcyxchat)
4. [Flutter App Architecture](#flutter-app-architecture)
5. [FFI Bridge](#ffi-bridge)
6. [Platform Setup](#platform-setup)
7. [Build Pipeline](#build-pipeline)
8. [Development Workflow](#development-workflow)

---

## Project Structure

```
cyxchat/
├── CYXCHAT.md                    # Main design document
├── SETUP.md                      # This file
├── README.md                     # Project overview
│
├── lib/                          # C library (libcyxchat)
│   ├── include/
│   │   └── cyxchat/
│   │       ├── chat.h            # Chat message types and APIs
│   │       ├── contact.h         # Contact management
│   │       ├── group.h           # Group chat APIs
│   │       ├── file.h            # File transfer APIs
│   │       └── presence.h        # Presence/status APIs
│   ├── src/
│   │   ├── chat.c                # Chat implementation
│   │   ├── contact.c             # Contact management
│   │   ├── group.c               # Group chat logic
│   │   ├── file.c                # File transfer
│   │   ├── presence.c            # Presence management
│   │   └── offline.c             # Offline message handling
│   ├── CMakeLists.txt            # C library build
│   └── tests/
│       ├── test_chat.c
│       ├── test_group.c
│       └── test_file.c
│
├── app/                          # Flutter application
│   ├── lib/
│   │   ├── main.dart             # App entry point
│   │   ├── app.dart              # App configuration
│   │   │
│   │   ├── core/                 # Core functionality
│   │   │   ├── ffi/              # FFI bindings
│   │   │   │   ├── bindings.dart # Generated FFI bindings
│   │   │   │   ├── chat_ffi.dart # Chat-specific FFI wrapper
│   │   │   │   └── types.dart    # Dart equivalents of C types
│   │   │   ├── database/         # Local storage
│   │   │   │   ├── database.dart # SQLite setup
│   │   │   │   ├── tables.dart   # Table definitions
│   │   │   │   └── queries.dart  # Common queries
│   │   │   ├── services/         # Business logic
│   │   │   │   ├── chat_service.dart
│   │   │   │   ├── contact_service.dart
│   │   │   │   ├── group_service.dart
│   │   │   │   └── notification_service.dart
│   │   │   └── models/           # Data models
│   │   │       ├── message.dart
│   │   │       ├── contact.dart
│   │   │       ├── conversation.dart
│   │   │       └── group.dart
│   │   │
│   │   ├── features/             # Feature modules
│   │   │   ├── chat/
│   │   │   │   ├── chat_list_screen.dart
│   │   │   │   ├── chat_detail_screen.dart
│   │   │   │   └── widgets/
│   │   │   ├── contacts/
│   │   │   │   ├── contacts_screen.dart
│   │   │   │   ├── add_contact_screen.dart
│   │   │   │   └── widgets/
│   │   │   ├── groups/
│   │   │   │   ├── create_group_screen.dart
│   │   │   │   ├── group_info_screen.dart
│   │   │   │   └── widgets/
│   │   │   ├── profile/
│   │   │   │   ├── profile_screen.dart
│   │   │   │   ├── qr_code_screen.dart
│   │   │   │   └── widgets/
│   │   │   └── settings/
│   │   │       ├── settings_screen.dart
│   │   │       └── screens/
│   │   │
│   │   ├── shared/               # Shared components
│   │   │   ├── widgets/          # Reusable widgets
│   │   │   ├── theme/            # App theme
│   │   │   └── utils/            # Utilities
│   │   │
│   │   └── providers/            # Riverpod providers
│   │       ├── chat_provider.dart
│   │       ├── contact_provider.dart
│   │       └── settings_provider.dart
│   │
│   ├── test/                     # Flutter tests
│   │   ├── unit/
│   │   ├── widget/
│   │   └── integration/
│   │
│   ├── android/                  # Android-specific
│   ├── ios/                      # iOS-specific
│   ├── linux/                    # Linux-specific
│   ├── macos/                    # macOS-specific
│   ├── windows/                  # Windows-specific
│   │
│   ├── pubspec.yaml              # Flutter dependencies
│   └── ffigen.yaml               # FFI generator config
│
├── scripts/                      # Build and utility scripts
│   ├── build_lib.sh              # Build C library
│   ├── generate_ffi.sh           # Generate FFI bindings
│   ├── setup_dev.sh              # Development setup
│   └── package.sh                # Package for release
│
└── docs/                         # Additional documentation
    ├── api/                      # API documentation
    ├── architecture/             # Architecture diagrams
    └── guides/                   # Developer guides
```

---

## Technology Stack

### Core Technologies

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **UI Framework** | Flutter | 3.24+ | Cross-platform UI |
| **Language (App)** | Dart | 3.5+ | App development |
| **Language (Core)** | C | C11 | Protocol implementation |
| **State Management** | Riverpod | 2.5+ | Reactive state |
| **Local Database** | SQLite | 3.x | Message storage |
| **DB Encryption** | SQLCipher | 4.x | Encrypted database |
| **FFI Generation** | ffigen | 11.0+ | C-to-Dart bindings |
| **Crypto Library** | libsodium | 1.0.18+ | Cryptographic primitives |

### Flutter Dependencies

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # Database
  sqflite: ^2.3.3
  sqflite_sqlcipher: ^2.2.1
  path: ^1.9.0

  # FFI
  ffi: ^2.1.2

  # UI Components
  go_router: ^14.2.0
  mobile_scanner: ^5.1.1        # QR code scanning
  qr_flutter: ^4.1.0            # QR code generation
  cached_network_image: ^3.3.1
  flutter_local_notifications: ^17.2.1

  # Utilities
  uuid: ^4.4.0
  intl: ^0.19.0
  collection: ^1.18.0
  equatable: ^2.0.5
  freezed_annotation: ^2.4.1
  json_annotation: ^4.9.0
  shared_preferences: ^2.2.3
  path_provider: ^2.1.3
  permission_handler: ^11.3.1

  # Audio (voice messages)
  record: ^5.1.0
  audioplayers: ^6.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # Code Generation
  build_runner: ^2.4.9
  freezed: ^2.5.2
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.0
  ffigen: ^11.0.0

  # Testing
  mockito: ^5.4.4
  integration_test:
    sdk: flutter

  # Linting
  flutter_lints: ^3.0.2
```

### C Library Dependencies

| Library | Version | Purpose |
|---------|---------|---------|
| libsodium | 1.0.18+ | Cryptography |
| libcyxwiz | (local) | Core protocol |

---

## C Extensions (libcyxchat)

### New C Files to Create

The chat functionality extends libcyxwiz with chat-specific modules.

### Header: `include/cyxchat/chat.h`

```c
#ifndef CYXCHAT_CHAT_H
#define CYXCHAT_CHAT_H

#include <cyxwiz/types.h>
#include <cyxwiz/onion.h>
#include <cyxwiz/routing.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Message Types (0x10-0x1F range)
 * ============================================================ */

#define CYXCHAT_MSG_CHAT         0x10
#define CYXCHAT_MSG_ACK          0x11
#define CYXCHAT_MSG_READ         0x12
#define CYXCHAT_MSG_TYPING       0x13
#define CYXCHAT_MSG_FILE_META    0x14
#define CYXCHAT_MSG_FILE_CHUNK   0x15
#define CYXCHAT_MSG_GROUP_MSG    0x16
#define CYXCHAT_MSG_GROUP_INVITE 0x17
#define CYXCHAT_MSG_GROUP_JOIN   0x18
#define CYXCHAT_MSG_GROUP_LEAVE  0x19
#define CYXCHAT_MSG_PRESENCE     0x1A
#define CYXCHAT_MSG_KEY_UPDATE   0x1B
#define CYXCHAT_MSG_REACTION     0x1C
#define CYXCHAT_MSG_DELETE       0x1D
#define CYXCHAT_MSG_EDIT         0x1E

/* Protocol version */
#define CYXCHAT_PROTOCOL_VERSION 1

/* ============================================================
 * Constants
 * ============================================================ */

#define CYXCHAT_MSG_ID_SIZE      8
#define CYXCHAT_MAX_TEXT_LEN     28    /* Per-packet (3-hop onion) */
#define CYXCHAT_MAX_CHUNK_SIZE   48
#define CYXCHAT_MAX_CHUNKS       16
#define CYXCHAT_MAX_DIRECT_FILE  768   /* 48 * 16 */
#define CYXCHAT_MAX_GROUP_MEMBERS 50
#define CYXCHAT_MAX_GROUP_NAME   64

/* Timeouts (ms) */
#define CYXCHAT_ACK_TIMEOUT_MS      10000
#define CYXCHAT_CHUNK_TIMEOUT_MS    10000
#define CYXCHAT_TYPING_TIMEOUT_MS   3000
#define CYXCHAT_PRESENCE_TIMEOUT_MS 60000

/* Retry limits */
#define CYXCHAT_MAX_MSG_RETRIES     4
#define CYXCHAT_MAX_CHUNK_RETRIES   3

/* ============================================================
 * Status Enums
 * ============================================================ */

typedef enum {
    CYXCHAT_STATUS_SENDING   = 0,
    CYXCHAT_STATUS_SENT      = 1,
    CYXCHAT_STATUS_DELIVERED = 2,
    CYXCHAT_STATUS_READ      = 3,
    CYXCHAT_STATUS_FAILED    = 4
} cyxchat_msg_status_t;

typedef enum {
    CYXCHAT_PRESENCE_OFFLINE = 0,
    CYXCHAT_PRESENCE_ONLINE  = 1,
    CYXCHAT_PRESENCE_AWAY    = 2,
    CYXCHAT_PRESENCE_BUSY    = 3
} cyxchat_presence_status_t;

/* ============================================================
 * Message Structures
 * ============================================================ */

/* Message header (common to all messages) */
typedef struct {
    uint8_t  type;              /* Message type (0x10-0x1F) */
    uint8_t  version;           /* Protocol version */
    uint8_t  flags;             /* Message flags */
    uint8_t  reserved;          /* Padding */
    uint64_t timestamp;         /* Unix timestamp (ms) */
    uint8_t  msg_id[CYXCHAT_MSG_ID_SIZE];  /* Random message ID */
} cyxchat_msg_header_t;         /* 20 bytes */

/* Direct text message */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t text_len;
    uint8_t text[CYXCHAT_MAX_TEXT_LEN];
} cyxchat_chat_msg_t;

/* Delivery/read acknowledgment */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t ack_msg_id[CYXCHAT_MSG_ID_SIZE];
    uint8_t status;             /* cyxchat_msg_status_t */
} cyxchat_ack_msg_t;

/* Typing indicator */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t is_typing;          /* 1=typing, 0=stopped */
} cyxchat_typing_msg_t;

/* Presence update */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t status;             /* cyxchat_presence_status_t */
    uint8_t custom_len;
    uint8_t custom[32];         /* Custom status text */
} cyxchat_presence_msg_t;

/* ============================================================
 * Chat Context
 * ============================================================ */

typedef struct cyxchat_ctx cyxchat_ctx_t;

/* Callback types */
typedef void (*cyxchat_msg_callback_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_chat_msg_t *msg,
    void *user_data
);

typedef void (*cyxchat_ack_callback_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *msg_id,
    cyxchat_msg_status_t status,
    void *user_data
);

typedef void (*cyxchat_typing_callback_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    int is_typing,
    void *user_data
);

typedef void (*cyxchat_presence_callback_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    cyxchat_presence_status_t status,
    void *user_data
);

/* ============================================================
 * Core API
 * ============================================================ */

/**
 * Create chat context
 * @param ctx Output context pointer
 * @param onion Onion routing context (from libcyxwiz)
 * @param local_id Local node ID
 * @return 0 on success, error code on failure
 */
int cyxchat_create(
    cyxchat_ctx_t **ctx,
    cyxwiz_onion_ctx_t *onion,
    const cyxwiz_node_id_t *local_id
);

/**
 * Destroy chat context
 */
void cyxchat_destroy(cyxchat_ctx_t *ctx);

/**
 * Poll for incoming messages (call from event loop)
 * @param ctx Chat context
 * @param current_time_ms Current time in milliseconds
 * @return Number of events processed
 */
int cyxchat_poll(cyxchat_ctx_t *ctx, uint64_t current_time_ms);

/* ============================================================
 * Messaging API
 * ============================================================ */

/**
 * Send text message
 * @param ctx Chat context
 * @param to Recipient node ID
 * @param text Message text (UTF-8)
 * @param text_len Text length in bytes
 * @param msg_id_out Output: generated message ID (8 bytes)
 * @return 0 on success
 */
int cyxchat_send_message(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *text,
    size_t text_len,
    uint8_t *msg_id_out
);

/**
 * Send acknowledgment
 * @param ctx Chat context
 * @param to Recipient node ID
 * @param msg_id Message ID being acknowledged
 * @param status Delivery status
 */
int cyxchat_send_ack(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const uint8_t *msg_id,
    cyxchat_msg_status_t status
);

/**
 * Send typing indicator
 * @param ctx Chat context
 * @param to Recipient node ID
 * @param is_typing 1 if typing, 0 if stopped
 */
int cyxchat_send_typing(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    int is_typing
);

/**
 * Update presence status
 * @param ctx Chat context
 * @param status New presence status
 * @param custom Optional custom status text (can be NULL)
 */
int cyxchat_set_presence(
    cyxchat_ctx_t *ctx,
    cyxchat_presence_status_t status,
    const char *custom
);

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_set_msg_callback(
    cyxchat_ctx_t *ctx,
    cyxchat_msg_callback_t callback,
    void *user_data
);

void cyxchat_set_ack_callback(
    cyxchat_ctx_t *ctx,
    cyxchat_ack_callback_t callback,
    void *user_data
);

void cyxchat_set_typing_callback(
    cyxchat_ctx_t *ctx,
    cyxchat_typing_callback_t callback,
    void *user_data
);

void cyxchat_set_presence_callback(
    cyxchat_ctx_t *ctx,
    cyxchat_presence_callback_t callback,
    void *user_data
);

/* ============================================================
 * Utility Functions
 * ============================================================ */

/**
 * Generate random message ID
 */
void cyxchat_generate_msg_id(uint8_t *msg_id);

/**
 * Get current timestamp in milliseconds
 */
uint64_t cyxchat_timestamp_ms(void);

/**
 * Convert node ID to hex string
 */
void cyxchat_node_id_to_hex(
    const cyxwiz_node_id_t *id,
    char *hex_out,
    size_t hex_len
);

/**
 * Parse node ID from hex string
 */
int cyxchat_node_id_from_hex(
    const char *hex,
    cyxwiz_node_id_t *id_out
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_CHAT_H */
```

### Header: `include/cyxchat/contact.h`

```c
#ifndef CYXCHAT_CONTACT_H
#define CYXCHAT_CONTACT_H

#include <cyxwiz/types.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CYXCHAT_MAX_DISPLAY_NAME 64
#define CYXCHAT_MAX_CONTACTS     256

typedef struct {
    cyxwiz_node_id_t node_id;
    uint8_t public_key[32];
    char display_name[CYXCHAT_MAX_DISPLAY_NAME];
    int verified;               /* Key verified by user */
    int blocked;
    uint64_t added_at;
    uint64_t last_seen;
    cyxchat_presence_status_t presence;
} cyxchat_contact_t;

typedef struct cyxchat_contact_list cyxchat_contact_list_t;

/* Create/destroy contact list */
int cyxchat_contact_list_create(cyxchat_contact_list_t **list);
void cyxchat_contact_list_destroy(cyxchat_contact_list_t *list);

/* Contact management */
int cyxchat_contact_add(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    const uint8_t *public_key,
    const char *display_name
);

int cyxchat_contact_remove(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

cyxchat_contact_t* cyxchat_contact_find(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

int cyxchat_contact_set_blocked(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int blocked
);

int cyxchat_contact_set_verified(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int verified
);

/* Iteration */
size_t cyxchat_contact_count(cyxchat_contact_list_t *list);
cyxchat_contact_t* cyxchat_contact_get(
    cyxchat_contact_list_t *list,
    size_t index
);

/* Safety number calculation */
void cyxchat_compute_safety_number(
    const uint8_t *our_pubkey,
    const uint8_t *their_pubkey,
    char *safety_number_out,
    size_t out_len
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_CONTACT_H */
```

### Header: `include/cyxchat/group.h`

```c
#ifndef CYXCHAT_GROUP_H
#define CYXCHAT_GROUP_H

#include <cyxwiz/types.h>
#include "chat.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CYXCHAT_GROUP_ID_SIZE    8
#define CYXCHAT_GROUP_KEY_SIZE   32

typedef struct {
    uint8_t group_id[CYXCHAT_GROUP_ID_SIZE];
    char name[CYXCHAT_MAX_GROUP_NAME];
    uint8_t group_key[CYXCHAT_GROUP_KEY_SIZE];
    uint32_t key_version;
    cyxwiz_node_id_t creator;
    cyxwiz_node_id_t members[CYXCHAT_MAX_GROUP_MEMBERS];
    uint8_t member_count;
    cyxwiz_node_id_t admins[5];
    uint8_t admin_count;
    uint64_t created_at;
} cyxchat_group_t;

typedef struct cyxchat_group_ctx cyxchat_group_ctx_t;

/* Callbacks */
typedef void (*cyxchat_group_msg_callback_t)(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *group_id,
    const cyxwiz_node_id_t *from,
    const char *text,
    size_t text_len,
    void *user_data
);

typedef void (*cyxchat_group_invite_callback_t)(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *group_id,
    const cyxwiz_node_id_t *from,
    const char *group_name,
    void *user_data
);

/* Group management */
int cyxchat_group_ctx_create(
    cyxchat_group_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
);

void cyxchat_group_ctx_destroy(cyxchat_group_ctx_t *ctx);

int cyxchat_group_create(
    cyxchat_group_ctx_t *ctx,
    const char *name,
    uint8_t *group_id_out
);

int cyxchat_group_invite(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *group_id,
    const cyxwiz_node_id_t *member
);

int cyxchat_group_remove_member(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *group_id,
    const cyxwiz_node_id_t *member
);

int cyxchat_group_leave(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *group_id
);

int cyxchat_group_send_message(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *group_id,
    const char *text,
    size_t text_len
);

int cyxchat_group_rotate_key(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *group_id
);

/* Callbacks */
void cyxchat_group_set_msg_callback(
    cyxchat_group_ctx_t *ctx,
    cyxchat_group_msg_callback_t callback,
    void *user_data
);

void cyxchat_group_set_invite_callback(
    cyxchat_group_ctx_t *ctx,
    cyxchat_group_invite_callback_t callback,
    void *user_data
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_GROUP_H */
```

### CMakeLists.txt for libcyxchat

```cmake
cmake_minimum_required(VERSION 3.16)
project(cyxchat C)

set(CMAKE_C_STANDARD 11)

# Find libcyxwiz (parent project)
find_library(CYXWIZ_LIB cyxwiz HINTS ${CMAKE_SOURCE_DIR}/../build)
find_path(CYXWIZ_INCLUDE cyxwiz/types.h HINTS ${CMAKE_SOURCE_DIR}/../include)

# Find libsodium
find_package(PkgConfig)
pkg_check_modules(SODIUM REQUIRED libsodium)

# Library sources
set(CYXCHAT_SOURCES
    src/chat.c
    src/contact.c
    src/group.c
    src/file.c
    src/presence.c
    src/offline.c
)

# Shared library (for FFI)
add_library(cyxchat SHARED ${CYXCHAT_SOURCES})

target_include_directories(cyxchat PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CYXWIZ_INCLUDE}
    ${SODIUM_INCLUDE_DIRS}
)

target_link_libraries(cyxchat
    ${CYXWIZ_LIB}
    ${SODIUM_LIBRARIES}
)

# Install
install(TARGETS cyxchat
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(DIRECTORY include/cyxchat DESTINATION include)

# Tests
enable_testing()
add_subdirectory(tests)
```

---

## Flutter App Architecture

### State Management with Riverpod

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      State Management Architecture                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Providers (Riverpod)                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │  cyxchatServiceProvider ──► FFI Bridge ──► libcyxchat          │   │
│  │         │                                                        │   │
│  │         ├── chatProvider (AsyncNotifier)                        │   │
│  │         │       └── conversations, messages                     │   │
│  │         │                                                        │   │
│  │         ├── contactsProvider (AsyncNotifier)                    │   │
│  │         │       └── contact list                                │   │
│  │         │                                                        │   │
│  │         ├── groupsProvider (AsyncNotifier)                      │   │
│  │         │       └── group list                                  │   │
│  │         │                                                        │   │
│  │         └── settingsProvider (StateNotifier)                    │   │
│  │                 └── app settings                                │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Data Flow:                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │  UI Widget ──► Provider ──► Service ──► FFI ──► C Library       │   │
│  │      │             │            │                                │   │
│  │      │             │            └── SQLite (persistence)        │   │
│  │      │             │                                             │   │
│  │      │             └── notifyListeners()                        │   │
│  │      │                                                           │   │
│  │      └── ref.watch() rebuilds on change                         │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Example Provider Implementation

```dart
// lib/providers/chat_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../core/services/chat_service.dart';
import '../core/models/conversation.dart';
import '../core/models/message.dart';

part 'chat_provider.g.dart';

@riverpod
class ChatNotifier extends _$ChatNotifier {
  late ChatService _chatService;

  @override
  Future<List<Conversation>> build() async {
    _chatService = ref.watch(chatServiceProvider);
    return _chatService.getConversations();
  }

  Future<void> sendMessage(String peerId, String text) async {
    await _chatService.sendMessage(peerId, text);
    ref.invalidateSelf(); // Refresh conversation list
  }

  Future<void> markAsRead(String conversationId) async {
    await _chatService.markAsRead(conversationId);
    ref.invalidateSelf();
  }
}

@riverpod
Stream<List<Message>> messages(MessagesRef ref, String conversationId) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.watchMessages(conversationId);
}

@riverpod
class TypingNotifier extends _$TypingNotifier {
  @override
  Map<String, bool> build() => {};

  void setTyping(String peerId, bool isTyping) {
    state = {...state, peerId: isTyping};

    // Auto-clear after timeout
    if (isTyping) {
      Future.delayed(const Duration(seconds: 3), () {
        if (state[peerId] == true) {
          state = {...state, peerId: false};
        }
      });
    }
  }
}
```

---

## FFI Bridge

### FFI Generator Configuration

```yaml
# app/ffigen.yaml

name: CyxchatBindings
description: FFI bindings for libcyxchat
output: 'lib/core/ffi/bindings.dart'

headers:
  entry-points:
    - '../lib/include/cyxchat/chat.h'
    - '../lib/include/cyxchat/contact.h'
    - '../lib/include/cyxchat/group.h'
  include-directives:
    - '../lib/include/cyxchat/*.h'
    - '../../include/cyxwiz/*.h'

compiler-opts:
  - '-I../lib/include'
  - '-I../../include'

preamble: |
  // AUTO-GENERATED - DO NOT EDIT
  // Generated by ffigen

type-map:
  'size_t':
    lib: 'ffi'
    dart-type: 'int'
    native-type: 'Size'

functions:
  include:
    - 'cyxchat_*'
  exclude:
    - 'cyxchat_internal_*'

structs:
  include:
    - 'cyxchat_*'
    - 'cyxwiz_node_id_t'

enums:
  include:
    - 'cyxchat_*'
```

### FFI Wrapper Example

```dart
// lib/core/ffi/chat_ffi.dart

import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'bindings.dart';

class CyxchatFFI {
  static CyxchatFFI? _instance;
  late final CyxchatBindings _bindings;
  late final DynamicLibrary _lib;

  Pointer<cyxchat_ctx_t>? _ctx;
  final _receivePort = ReceivePort();

  // Callbacks
  void Function(String from, String text, String msgId)? onMessage;
  void Function(String from, String msgId, int status)? onAck;
  void Function(String from, bool isTyping)? onTyping;

  CyxchatFFI._() {
    _lib = _loadLibrary();
    _bindings = CyxchatBindings(_lib);
  }

  static CyxchatFFI get instance {
    _instance ??= CyxchatFFI._();
    return _instance!;
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('cyxchat.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libcyxchat.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libcyxchat.dylib');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libcyxchat.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Platform not supported');
  }

  Future<void> initialize(Pointer<Void> onionCtx, Uint8List nodeId) async {
    final nodeIdPtr = calloc<Uint8>(32);
    nodeIdPtr.asTypedList(32).setAll(0, nodeId);

    final ctxPtr = calloc<Pointer<cyxchat_ctx_t>>();

    final result = _bindings.cyxchat_create(
      ctxPtr,
      onionCtx.cast(),
      nodeIdPtr.cast(),
    );

    if (result != 0) {
      calloc.free(nodeIdPtr);
      calloc.free(ctxPtr);
      throw Exception('Failed to create chat context: $result');
    }

    _ctx = ctxPtr.value;
    calloc.free(nodeIdPtr);
    calloc.free(ctxPtr);

    // Set up callbacks
    _setupCallbacks();
  }

  void _setupCallbacks() {
    // Message callback
    final msgCallback = Pointer.fromFunction<
        Void Function(
            Pointer<cyxchat_ctx_t>,
            Pointer<cyxwiz_node_id_t>,
            Pointer<cyxchat_chat_msg_t>,
            Pointer<Void>)
    >(_onMessageNative);

    _bindings.cyxchat_set_msg_callback(_ctx!, msgCallback, nullptr);
  }

  static void _onMessageNative(
    Pointer<cyxchat_ctx_t> ctx,
    Pointer<cyxwiz_node_id_t> from,
    Pointer<cyxchat_chat_msg_t> msg,
    Pointer<Void> userData,
  ) {
    // Convert to Dart types and call callback
    final instance = CyxchatFFI.instance;
    if (instance.onMessage != null) {
      final fromHex = _nodeIdToHex(from);
      final text = msg.ref.text.cast<Utf8>().toDartString(
        length: msg.ref.text_len,
      );
      final msgId = _bytesToHex(msg.ref.header.msg_id, 8);
      instance.onMessage!(fromHex, text, msgId);
    }
  }

  Future<String> sendMessage(String to, String text) async {
    final toPtr = _hexToNodeId(to);
    final textPtr = text.toNativeUtf8();
    final msgIdPtr = calloc<Uint8>(8);

    final result = _bindings.cyxchat_send_message(
      _ctx!,
      toPtr.cast(),
      textPtr.cast(),
      text.length,
      msgIdPtr,
    );

    final msgId = _bytesToHex(msgIdPtr, 8);

    calloc.free(toPtr);
    calloc.free(textPtr);
    calloc.free(msgIdPtr);

    if (result != 0) {
      throw Exception('Failed to send message: $result');
    }

    return msgId;
  }

  void poll() {
    if (_ctx != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _bindings.cyxchat_poll(_ctx!, now);
    }
  }

  void dispose() {
    if (_ctx != null) {
      _bindings.cyxchat_destroy(_ctx!);
      _ctx = null;
    }
  }

  // Helper methods
  static String _nodeIdToHex(Pointer<cyxwiz_node_id_t> ptr) {
    final bytes = ptr.cast<Uint8>().asTypedList(32);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Pointer<Uint8> _hexToNodeId(String hex) {
    final ptr = calloc<Uint8>(32);
    for (var i = 0; i < 32; i++) {
      ptr[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return ptr;
  }

  static String _bytesToHex(Pointer<Uint8> ptr, int len) {
    final bytes = ptr.asTypedList(len);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
```

---

## Platform Setup

### Windows

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Windows Development Setup                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Requirements:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Windows 10/11 (64-bit)                                       │   │
│  │  • Visual Studio 2022 with C++ workload                        │   │
│  │  • Flutter SDK 3.24+                                            │   │
│  │  • CMake 3.16+                                                  │   │
│  │  • vcpkg (for dependencies)                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Install Dependencies:                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Install vcpkg                                                 │   │
│  │  git clone https://github.com/microsoft/vcpkg                   │   │
│  │  .\vcpkg\bootstrap-vcpkg.bat                                    │   │
│  │                                                                  │   │
│  │  # Install libsodium                                            │   │
│  │  .\vcpkg\vcpkg install libsodium:x64-windows                   │   │
│  │                                                                  │   │
│  │  # Set environment variable                                     │   │
│  │  set VCPKG_ROOT=C:\path\to\vcpkg                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Build C Library:                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cd cyxchat/lib                                                  │   │
│  │  cmake -B build -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\    │   │
│  │        cmake\vcpkg.cmake                                        │   │
│  │  cmake --build build --config Release                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Copy DLL to Flutter:                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  copy lib\build\Release\cyxchat.dll app\windows\                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### macOS

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      macOS Development Setup                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Requirements:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • macOS 12+ (Monterey or later)                                │   │
│  │  • Xcode 14+ with command line tools                            │   │
│  │  • Flutter SDK 3.24+                                            │   │
│  │  • Homebrew                                                      │   │
│  │  • CMake 3.16+                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Install Dependencies:                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Install Xcode CLI tools                                      │   │
│  │  xcode-select --install                                         │   │
│  │                                                                  │   │
│  │  # Install dependencies                                         │   │
│  │  brew install cmake libsodium                                   │   │
│  │                                                                  │   │
│  │  # Install Flutter                                              │   │
│  │  brew install flutter                                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Build C Library:                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cd cyxchat/lib                                                  │   │
│  │  cmake -B build -DCMAKE_BUILD_TYPE=Release                      │   │
│  │  cmake --build build                                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Copy dylib to Flutter:                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cp lib/build/libcyxchat.dylib app/macos/Runner/               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Code Signing (for distribution):                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Requires Apple Developer account                             │   │
│  │  • Enable Hardened Runtime                                       │   │
│  │  • Sign dylib with: codesign -s "Developer ID" libcyxchat.dylib│   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Linux

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Linux Development Setup                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Requirements:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Ubuntu 22.04+ / Fedora 38+ / Arch (or equivalent)            │   │
│  │  • GCC 11+ or Clang 14+                                         │   │
│  │  • Flutter SDK 3.24+                                            │   │
│  │  • CMake 3.16+                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Install Dependencies (Ubuntu/Debian):                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  sudo apt update                                                 │   │
│  │  sudo apt install -y build-essential cmake git                  │   │
│  │  sudo apt install -y libsodium-dev                              │   │
│  │  sudo apt install -y libgtk-3-dev libblkid-dev liblzma-dev     │   │
│  │                                                                  │   │
│  │  # For Bluetooth support                                        │   │
│  │  sudo apt install -y libbluetooth-dev                          │   │
│  │                                                                  │   │
│  │  # For WiFi Direct support                                      │   │
│  │  sudo apt install -y wpasupplicant                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Install Flutter:                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Via snap                                                      │   │
│  │  sudo snap install flutter --classic                            │   │
│  │                                                                  │   │
│  │  # Or manual                                                     │   │
│  │  git clone https://github.com/flutter/flutter.git               │   │
│  │  export PATH="$PATH:$HOME/flutter/bin"                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Build C Library:                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cd cyxchat/lib                                                  │   │
│  │  cmake -B build -DCMAKE_BUILD_TYPE=Release                      │   │
│  │  cmake --build build                                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Copy .so to Flutter:                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cp lib/build/libcyxchat.so app/linux/                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Android

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Android Development Setup                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Requirements:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Android Studio Arctic Fox+                                   │   │
│  │  • Android SDK 21+ (Lollipop)                                   │   │
│  │  • Android NDK 25+                                              │   │
│  │  • Flutter SDK 3.24+                                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Install NDK:                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Via Android Studio:                                          │   │
│  │  # Settings → Appearance → SDK Manager → SDK Tools → NDK        │   │
│  │                                                                  │   │
│  │  # Or via command line:                                         │   │
│  │  sdkmanager --install "ndk;25.2.9519653"                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Cross-compile libsodium:                                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Clone libsodium                                              │   │
│  │  git clone https://github.com/jedisct1/libsodium               │   │
│  │  cd libsodium                                                    │   │
│  │                                                                  │   │
│  │  # Build for Android (all ABIs)                                 │   │
│  │  ./dist-build/android-armv7-a.sh                                │   │
│  │  ./dist-build/android-armv8-a.sh                                │   │
│  │  ./dist-build/android-x86.sh                                    │   │
│  │  ./dist-build/android-x86_64.sh                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  CMake Android Build:                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # In app/android/app/build.gradle:                             │   │
│  │  android {                                                       │   │
│  │      externalNativeBuild {                                      │   │
│  │          cmake {                                                 │   │
│  │              path "../../lib/CMakeLists.txt"                    │   │
│  │          }                                                       │   │
│  │      }                                                           │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  JNI Bridge (if needed):                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Flutter handles FFI directly, no JNI needed                  │   │
│  │  # .so files placed in app/android/app/src/main/jniLibs/       │   │
│  │  # per ABI: armeabi-v7a, arm64-v8a, x86, x86_64                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### iOS

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      iOS Development Setup                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Requirements:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • macOS (required for iOS development)                         │   │
│  │  • Xcode 14+                                                     │   │
│  │  • iOS 12+ deployment target                                    │   │
│  │  • Apple Developer Account (for device testing)                 │   │
│  │  • Flutter SDK 3.24+                                            │   │
│  │  • CocoaPods                                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Install CocoaPods:                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  sudo gem install cocoapods                                     │   │
│  │  # Or via Homebrew                                              │   │
│  │  brew install cocoapods                                         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Build libsodium for iOS:                                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Clone libsodium                                              │   │
│  │  git clone https://github.com/jedisct1/libsodium               │   │
│  │  cd libsodium                                                    │   │
│  │                                                                  │   │
│  │  # Build universal framework                                    │   │
│  │  ./dist-build/apple-xcframework.sh                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Podfile Setup:                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # app/ios/Podfile                                              │   │
│  │  platform :ios, '12.0'                                          │   │
│  │                                                                  │   │
│  │  target 'Runner' do                                             │   │
│  │    use_frameworks!                                               │   │
│  │    use_modular_headers!                                         │   │
│  │                                                                  │   │
│  │    flutter_install_all_ios_pods File.dirname(...)               │   │
│  │                                                                  │   │
│  │    # Add libsodium                                              │   │
│  │    pod 'libsodium', '~> 1.0.18'                                │   │
│  │  end                                                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Static Library Integration:                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # libcyxchat must be built as static library for iOS           │   │
│  │  # Add to Xcode project as embedded framework                   │   │
│  │  # Or include sources directly in Xcode build                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Permissions (Info.plist):                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  <!-- Bluetooth -->                                             │   │
│  │  <key>NSBluetoothAlwaysUsageDescription</key>                  │   │
│  │  <string>CyxChat uses Bluetooth for local messaging</string>   │   │
│  │                                                                  │   │
│  │  <!-- Camera (QR scanning) -->                                  │   │
│  │  <key>NSCameraUsageDescription</key>                            │   │
│  │  <string>CyxChat uses camera to scan QR codes</string>         │   │
│  │                                                                  │   │
│  │  <!-- Microphone (voice messages) -->                           │   │
│  │  <key>NSMicrophoneUsageDescription</key>                        │   │
│  │  <string>CyxChat uses microphone for voice messages</string>   │   │
│  │                                                                  │   │
│  │  <!-- Local Network (for WiFi discovery fallback) -->          │   │
│  │  <key>NSLocalNetworkUsageDescription</key>                      │   │
│  │  <string>CyxChat uses local network for peer discovery</string>│   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Build Pipeline

### CI/CD Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Build Pipeline                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │  Push to main ──► CI Triggered                                  │   │
│  │                        │                                         │   │
│  │                        ├──► Build C Library (all platforms)     │   │
│  │                        │       ├── Windows (x64)                │   │
│  │                        │       ├── macOS (universal)            │   │
│  │                        │       ├── Linux (x64)                  │   │
│  │                        │       ├── Android (4 ABIs)             │   │
│  │                        │       └── iOS (arm64)                  │   │
│  │                        │                                         │   │
│  │                        ├──► Generate FFI Bindings               │   │
│  │                        │                                         │   │
│  │                        ├──► Run C Tests                         │   │
│  │                        │                                         │   │
│  │                        ├──► Run Flutter Tests                   │   │
│  │                        │       ├── Unit tests                   │   │
│  │                        │       └── Widget tests                 │   │
│  │                        │                                         │   │
│  │                        └──► Build Flutter Apps                  │   │
│  │                                ├── Windows .exe                 │   │
│  │                                ├── macOS .app                   │   │
│  │                                ├── Linux .AppImage              │   │
│  │                                ├── Android .apk / .aab          │   │
│  │                                └── iOS .ipa                     │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### GitHub Actions Example

```yaml
# .github/workflows/build.yml

name: Build CyxChat

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-c-library:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies (Ubuntu)
        if: runner.os == 'Linux'
        run: sudo apt-get install -y libsodium-dev cmake

      - name: Install dependencies (macOS)
        if: runner.os == 'macOS'
        run: brew install libsodium cmake

      - name: Install dependencies (Windows)
        if: runner.os == 'Windows'
        run: |
          vcpkg install libsodium:x64-windows

      - name: Build C library
        run: |
          cd cyxchat/lib
          cmake -B build -DCMAKE_BUILD_TYPE=Release
          cmake --build build --config Release

      - name: Run C tests
        run: ctest --test-dir cyxchat/lib/build --output-on-failure

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: cyxchat-${{ runner.os }}
          path: cyxchat/lib/build/*cyxchat*

  build-flutter:
    needs: build-c-library
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: linux
          - os: macos-latest
            target: macos
          - os: windows-latest
            target: windows
    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'

      - name: Download C library
        uses: actions/download-artifact@v4
        with:
          name: cyxchat-${{ runner.os }}
          path: cyxchat/lib/build

      - name: Generate FFI bindings
        run: |
          cd cyxchat/app
          dart run ffigen

      - name: Run Flutter tests
        run: |
          cd cyxchat/app
          flutter test

      - name: Build Flutter app
        run: |
          cd cyxchat/app
          flutter build ${{ matrix.target }} --release

      - name: Upload Flutter app
        uses: actions/upload-artifact@v4
        with:
          name: cyxchat-app-${{ matrix.target }}
          path: cyxchat/app/build/${{ matrix.target }}/
```

---

## Development Workflow

### Daily Development

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Development Workflow                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Start Development                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Terminal 1: Build and watch C library                        │   │
│  │  cd cyxchat/lib                                                  │   │
│  │  cmake -B build && cmake --build build                          │   │
│  │                                                                  │   │
│  │  # Terminal 2: Run Flutter in development mode                  │   │
│  │  cd cyxchat/app                                                  │   │
│  │  flutter run -d <device>                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  2. After C API Changes                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Rebuild C library                                            │   │
│  │  cmake --build build                                            │   │
│  │                                                                  │   │
│  │  # Regenerate FFI bindings                                      │   │
│  │  cd ../app                                                       │   │
│  │  dart run ffigen                                                 │   │
│  │                                                                  │   │
│  │  # Hot restart Flutter app (not hot reload)                     │   │
│  │  # Press 'R' in flutter run terminal                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  3. After Dart/Flutter Changes                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Hot reload (press 'r') or hot restart (press 'R')            │   │
│  │  # Riverpod changes usually need hot restart                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  4. Running Tests                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # C tests                                                       │   │
│  │  ctest --test-dir cyxchat/lib/build                             │   │
│  │                                                                  │   │
│  │  # Flutter tests                                                 │   │
│  │  cd cyxchat/app                                                  │   │
│  │  flutter test                                                    │   │
│  │                                                                  │   │
│  │  # Integration tests                                            │   │
│  │  flutter test integration_test                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  5. Code Generation (after model changes)                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cd cyxchat/app                                                  │   │
│  │  dart run build_runner build --delete-conflicting-outputs       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Debugging Tips

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Debugging                                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  C Library Debugging:                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Build with debug symbols                                     │   │
│  │  cmake -B build -DCMAKE_BUILD_TYPE=Debug                        │   │
│  │                                                                  │   │
│  │  # Use GDB/LLDB                                                 │   │
│  │  gdb ./build/test_chat                                          │   │
│  │  lldb ./build/test_chat                                         │   │
│  │                                                                  │   │
│  │  # Enable verbose logging in libcyxchat                         │   │
│  │  export CYXCHAT_LOG_LEVEL=debug                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  FFI Debugging:                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Check library loading                                        │   │
│  │  # On Linux: LD_DEBUG=libs flutter run                          │   │
│  │  # On macOS: DYLD_PRINT_LIBRARIES=1 flutter run                 │   │
│  │                                                                  │   │
│  │  # Common issues:                                               │   │
│  │  • Library not found: Check path, use absolute paths            │   │
│  │  • Symbol not found: Check function export, rebuild             │   │
│  │  • Segfault: Check pointer handling, memory allocation          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Flutter Debugging:                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # Use Flutter DevTools                                         │   │
│  │  flutter run --observatory-port=8888                            │   │
│  │  # Open http://localhost:8888 in browser                        │   │
│  │                                                                  │   │
│  │  # Riverpod debugging                                           │   │
│  │  # Add ProviderObserver for logging                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Checklist: Before First Build

### C Library Setup
- [ ] libsodium installed and accessible
- [ ] libcyxwiz built (from parent project)
- [ ] CMakeLists.txt configured correctly
- [ ] Header files in include/cyxchat/

### Flutter Setup
- [ ] Flutter SDK installed (3.24+)
- [ ] Platform SDKs installed (Android Studio, Xcode, etc.)
- [ ] pubspec.yaml dependencies added
- [ ] ffigen.yaml configured

### FFI Bridge
- [ ] C header files accessible from ffigen
- [ ] Bindings generated successfully
- [ ] Library loading works on target platform

### Platform-Specific
- [ ] Windows: vcpkg + libsodium, DLL in windows/
- [ ] macOS: Homebrew + libsodium, dylib signed
- [ ] Linux: apt/dnf + libsodium, .so in linux/
- [ ] Android: NDK + cross-compiled libs, jniLibs/
- [ ] iOS: CocoaPods + libsodium, frameworks linked

---

## Next Steps

1. Create the `cyxchat/lib/` folder structure
2. Implement core C APIs (chat.c, contact.c)
3. Create Flutter project with `flutter create`
4. Set up FFI bindings generation
5. Build basic UI screens
6. Implement message send/receive flow
