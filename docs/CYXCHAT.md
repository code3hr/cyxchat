# CyxChat - Privacy-First Messaging on CyxWiz Mesh Network

## Overview

CyxChat is a decentralized, privacy-first messaging application built on the CyxWiz mesh network. It provides secure communication without central servers, phone numbers, or email addresses.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CyxChat Architecture                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                      Flutter UI Layer                            │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐│    │
│  │  │Chat List │  │Chat View │  │ Contacts │  │ Settings/Profile ││    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘│    │
│  └────────────────────────────┬────────────────────────────────────┘    │
│                               │ FFI Bridge                              │
│  ┌────────────────────────────┴────────────────────────────────────┐    │
│  │                     libcyxwiz (C Core)                           │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐│    │
│  │  │  Onion   │  │  Router  │  │ CyxCloud │  │   Crypto/Keys    ││    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘│    │
│  └────────────────────────────┬────────────────────────────────────┘    │
│                               │                                         │
│  ┌────────────────────────────┴────────────────────────────────────┐    │
│  │                     Transport Layer                              │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐│    │
│  │  │   UDP    │  │WiFi Direct│ │Bluetooth │  │      LoRa        ││    │
│  │  │(Internet)│  │  (Local) │  │ (Local)  │  │   (Long Range)   ││    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘│    │
│  └──────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Design Goals

| Goal | Description |
|------|-------------|
| **True Privacy** | No phone number, email, or central account required |
| **Works Worldwide** | Local mesh + internet via relays + NAT traversal |
| **Cross-Platform** | Desktop (Windows, macOS, Linux) + Mobile (iOS, Android) |
| **Offline Capable** | Messages queue locally and sync when reconnected |
| **Group Chat** | Private groups with forward-secret key rotation |
| **Censorship Resistant** | Multiple transports, no single point of failure |

## Core Concepts

### 1. Identity

CyxChat uses anonymous cryptographic identities instead of phone numbers or emails.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         User Identity                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Node ID (Primary Identity):                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  32 random bytes = 256-bit identity                              │   │
│  │  Example: a1b2c3d4e5f6...7890abcdef (64 hex chars)              │   │
│  │  Generated locally, never transmitted to any server              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Keypair:                                                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  X25519 keypair for key exchange                                 │   │
│  │  • Public key: shared with contacts                              │   │
│  │  • Private key: never leaves device                              │   │
│  │  • Rotated hourly for forward secrecy                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Optional Metadata:                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Display name (stored encrypted locally)                       │   │
│  │  • Avatar (stored encrypted locally)                             │   │
│  │  • Public profile (optional, stored in CyxCloud)                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2. Identity Creation Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    First Launch - Identity Creation                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Step 1: Generate Identity                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  node_id = crypto_random_bytes(32)                               │   │
│  │  (keypair_public, keypair_private) = crypto_box_keypair()       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Step 2: Secure Storage                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Platform      | Storage                                         │   │
│  │  ─────────────────────────────────────────────────────────────  │   │
│  │  Windows       | Windows Credential Manager                      │   │
│  │  macOS         | Keychain                                        │   │
│  │  Linux         | libsecret / GNOME Keyring                      │   │
│  │  iOS           | Keychain Services                               │   │
│  │  Android       | Android Keystore                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Step 3: Optional Profile                                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Set display name (local only by default)                      │   │
│  │  • Choose avatar (local only by default)                         │   │
│  │  • Optionally publish to CyxCloud directory                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Step 4: Backup (Optional but Recommended)                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Export recovery phrase (BIP39 mnemonic)                       │   │
│  │  • Or export encrypted backup file                               │   │
│  │  • Identity can be restored on new device                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## User Discovery

### Discovery Methods

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         User Discovery Methods                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐  │
│  │     LOCAL DISCOVERY         │  │       GLOBAL DISCOVERY          │  │
│  │     (No Internet)           │  │       (Internet Required)       │  │
│  ├─────────────────────────────┤  ├─────────────────────────────────┤  │
│  │                             │  │                                 │  │
│  │  WiFi Direct                │  │  Bootstrap Servers              │  │
│  │  • Scan for nearby peers    │  │  • Initial peer discovery       │  │
│  │  • ~100m range indoors      │  │  • NAT traversal (STUN)         │  │
│  │                             │  │                                 │  │
│  │  Bluetooth                  │  │  Relay Nodes                    │  │
│  │  • Discover nearby devices  │  │  • Bridge mesh networks         │  │
│  │  • ~10m range               │  │  • Store offline messages       │  │
│  │                             │  │                                 │  │
│  │  LoRa                       │  │  CyxCloud Directory             │  │
│  │  • Long-range beacons       │  │  • Opt-in public profiles       │  │
│  │  • ~10km line-of-sight      │  │  • Searchable by username       │  │
│  │                             │  │                                 │  │
│  │  ANNOUNCE Broadcasts        │  │  Friend Introductions           │  │
│  │  • "I'm here" messages      │  │  • Alice introduces Bob to Carol│  │
│  │  • Include public key       │  │  • Relay contact info securely  │  │
│  │                             │  │                                 │  │
│  └─────────────────────────────┘  └─────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Contact Exchange Methods

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Contact Exchange Methods                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. QR Code (Recommended)                                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Format: cyxchat://add/<node_id_hex>/<public_key_hex>           │   │
│  │                                                                  │   │
│  │  Alice shows QR ──► Bob scans ──► Bob has Alice's contact       │   │
│  │  Bob shows QR   ──► Alice scans ──► Alice has Bob's contact     │   │
│  │                                                                  │   │
│  │  QR contains: node_id (32B) + public_key (32B) = 128 hex chars  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  2. NFC Tap (Mobile)                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Same data as QR, transmitted via NFC                            │   │
│  │  Tap phones together ──► Both have each other's contact          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  3. Share Link                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cyxchat://add/a1b2c3d4.../e5f6g7h8...                          │   │
│  │  • Copy and paste via any channel                                │   │
│  │  • Opens CyxChat app with add contact dialog                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  4. Friend Introduction                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Alice wants to introduce Bob to Carol:                          │   │
│  │  1. Alice sends Carol's contact info to Bob (encrypted)          │   │
│  │  2. Alice sends Bob's contact info to Carol (encrypted)          │   │
│  │  3. Both can now communicate directly                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  5. Directory Search (Opt-in)                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Users who publish to CyxCloud directory can be found by:        │   │
│  │  • Username search                                               │   │
│  │  • Browse categories                                             │   │
│  │  Directory entry is encrypted, only searchable fields exposed   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Verification

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Key Verification                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Safety Numbers (like Signal):                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  safety_number = SHA256(sorted(alice_pubkey || bob_pubkey))      │   │
│  │                                                                  │   │
│  │  Display as: 12345 67890 12345 67890 12345 67890                │   │
│  │              12345 67890 12345 67890 12345 67890                │   │
│  │                                                                  │   │
│  │  Both parties should see identical numbers                       │   │
│  │  Compare in person or via trusted channel                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Key Change Notifications:                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Alert when contact's public key changes                       │   │
│  │  • Could indicate: new device, key rotation, or MITM attack      │   │
│  │  • User must approve new key before messages are sent            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Message Protocol

### Message Types (0x10-0x1F Range)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CyxChat Message Types                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Code   │ Name              │ Size   │ Description                      │
│  ───────┼───────────────────┼────────┼──────────────────────────────────│
│  0x10   │ CHAT_MSG          │ ≤48B   │ Direct text message              │
│  0x11   │ CHAT_ACK          │ 41B    │ Delivery acknowledgment          │
│  0x12   │ CHAT_READ         │ 41B    │ Read receipt                     │
│  0x13   │ CHAT_TYPING       │ 33B    │ Typing indicator                 │
│  0x14   │ CHAT_FILE_META    │ 64B    │ File metadata                    │
│  0x15   │ CHAT_FILE_CHUNK   │ 48B    │ File data chunk                  │
│  0x16   │ CHAT_GROUP_MSG    │ ≤48B   │ Group message                    │
│  0x17   │ CHAT_GROUP_INVITE │ 97B    │ Group invitation                 │
│  0x18   │ CHAT_GROUP_JOIN   │ 65B    │ Join acknowledgment              │
│  0x19   │ CHAT_GROUP_LEAVE  │ 41B    │ Leave notification               │
│  0x1A   │ CHAT_PRESENCE     │ 34B    │ Online/offline status            │
│  0x1B   │ CHAT_KEY_UPDATE   │ 64B    │ Key rotation notification        │
│  0x1C   │ CHAT_REACTION     │ 42B    │ Message reaction (emoji)         │
│  0x1D   │ CHAT_DELETE       │ 41B    │ Delete message request           │
│  0x1E   │ CHAT_EDIT         │ ≤64B   │ Edit message                     │
│  0x1F   │ (Reserved)        │ -      │ Future use                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Message Structures

```c
/* Base message header (all messages) */
typedef struct {
    uint8_t type;           /* Message type (0x10-0x1F) */
    uint8_t version;        /* Protocol version */
    uint8_t flags;          /* Message flags */
    uint8_t reserved;       /* Padding */
    uint64_t timestamp;     /* Unix timestamp (ms) */
    uint8_t msg_id[8];      /* Random message ID */
} cyxchat_msg_header_t;    /* 20 bytes */

/* Direct text message */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t text_len;       /* 1-28 bytes of text */
    uint8_t text[];         /* UTF-8 text (variable) */
} cyxchat_chat_msg_t;      /* 21 + text_len bytes, max 48B payload */

/* Delivery acknowledgment */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t ack_msg_id[8];  /* Message being acknowledged */
    uint8_t status;         /* 0=delivered, 1=read, 2=failed */
} cyxchat_chat_ack_t;      /* 29 bytes */

/* Typing indicator */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t is_typing;      /* 1=typing, 0=stopped */
} cyxchat_chat_typing_t;   /* 21 bytes */

/* File metadata */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t storage_id[8];  /* CyxCloud storage ID (for large files) */
    uint8_t file_key[32];   /* Decryption key */
    uint32_t file_size;     /* Total file size in bytes */
    uint8_t name_len;       /* Filename length */
    uint8_t name[];         /* UTF-8 filename (variable) */
} cyxchat_file_meta_t;     /* 65 + name_len bytes */

/* File chunk */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t file_id[8];     /* File identifier */
    uint16_t chunk_index;   /* Chunk number (0-based) */
    uint16_t total_chunks;  /* Total chunk count */
    uint8_t data_len;       /* Bytes in this chunk (max 48) */
    uint8_t data[];         /* Chunk data */
} cyxchat_file_chunk_t;    /* 33 + data_len bytes */

/* Group message */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t group_id[8];    /* Group identifier */
    uint8_t text_len;       /* Text length */
    uint8_t text[];         /* UTF-8 text */
} cyxchat_group_msg_t;     /* 29 + text_len bytes */

/* Group invitation */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t group_id[8];    /* Group identifier */
    uint8_t group_key[32];  /* Encrypted group key */
    uint8_t inviter_id[32]; /* Who sent the invite */
    uint8_t group_name_len; /* Group name length */
    uint8_t group_name[];   /* Group name */
} cyxchat_group_invite_t;  /* 93 + name_len bytes */

/* Presence update */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t status;         /* 0=offline, 1=online, 2=away, 3=busy */
    uint8_t custom_len;     /* Custom status length */
    uint8_t custom[];       /* Custom status text */
} cyxchat_presence_t;      /* 22 + custom_len bytes */
```

### Message Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Message Send Flow                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  SENDER (Alice)                                        RECIPIENT (Bob)  │
│                                                                          │
│  1. Create message                                                      │
│     ┌──────────────────────────────────────────────┐                   │
│     │ msg = { type: CHAT_MSG, text: "Hello!" }     │                   │
│     │ msg.msg_id = random(8)                        │                   │
│     │ msg.timestamp = now()                         │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  2. Encrypt for recipient                                               │
│     ┌──────────────────────────────────────────────┐                   │
│     │ shared_key = X25519(alice_private, bob_public)│                   │
│     │ encrypted = XChaCha20Poly1305(msg, shared_key)│                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  3. Wrap in onion layers (3 hops)                                       │
│     ┌──────────────────────────────────────────────┐                   │
│     │ Layer 3: Encrypt for Hop3 (with next=Bob)    │                   │
│     │ Layer 2: Encrypt for Hop2 (with next=Hop3)   │                   │
│     │ Layer 1: Encrypt for Hop1 (with next=Hop2)   │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  4. Send to first hop                                                   │
│     Alice ────► Hop1 ────► Hop2 ────► Hop3 ────► Bob                   │
│                                                                          │
│  5. Store locally (pending ACK)                                         │
│     ┌──────────────────────────────────────────────┐                   │
│     │ local_db.save(msg, status="sent")             │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  6. Receive ACK (via return path)                                       │
│     Bob ────► Hop3 ────► Hop2 ────► Hop1 ────► Alice                   │
│     ┌──────────────────────────────────────────────┐                   │
│     │ local_db.update(msg_id, status="delivered")   │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Long Messages (>48 bytes)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Long Message Handling                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Constraint: Max payload per onion packet = 48 bytes (3-hop routing)    │
│                                                                          │
│  Strategy: Fragment and reassemble                                      │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Original message: "This is a longer message that exceeds..."    │   │
│  │  (100 bytes)                                                     │   │
│  │                                                                  │   │
│  │  Fragment 1: [header(20) + frag_info(4) + data(24)]             │   │
│  │  Fragment 2: [header(20) + frag_info(4) + data(24)]             │   │
│  │  Fragment 3: [header(20) + frag_info(4) + data(24)]             │   │
│  │  Fragment 4: [header(20) + frag_info(4) + data(4)]              │   │
│  │                                                                  │   │
│  │  frag_info: { msg_id(8), frag_index(2), total_frags(2) }        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Reassembly:                                                            │
│  • Collect fragments by msg_id                                          │
│  • Order by frag_index                                                  │
│  • Timeout: 30 seconds for all fragments                               │
│  • Verify: MAC covers complete reassembled message                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Offline Messaging

### Store-and-Forward

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Offline Message Flow                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Scenario: Alice sends to Bob, but Bob is offline                       │
│                                                                          │
│  1. Alice sends message                                                 │
│     ┌──────────────────────────────────────────────┐                   │
│     │ Alice ──► Onion ──► ... ──► (Bob offline!)   │                   │
│     │ No ACK received after 10 seconds             │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  2. Store in CyxCloud                                                   │
│     ┌──────────────────────────────────────────────┐                   │
│     │ encrypted_msg = Encrypt(msg, bob_public_key)  │                   │
│     │ storage_id = CyxCloud.store(encrypted_msg)    │                   │
│     │ (Stored with K-of-N secret sharing)           │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  3. Leave notification hint at relay                                    │
│     ┌──────────────────────────────────────────────┐                   │
│     │ hint = { recipient: bob_id, storage_id, ttl } │                   │
│     │ relay.store_hint(hint)                        │                   │
│     │ (Multiple relays for redundancy)              │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  4. Bob comes online                                                    │
│     ┌──────────────────────────────────────────────┐                   │
│     │ hints = relay.get_hints(bob_id)               │                   │
│     │ for hint in hints:                            │                   │
│     │     encrypted = CyxCloud.retrieve(storage_id) │                   │
│     │     msg = Decrypt(encrypted, bob_private_key) │                   │
│     │     display(msg)                              │                   │
│     │     CyxCloud.delete(storage_id)               │                   │
│     │     send_ack_to_alice()                       │                   │
│     └──────────────────────────────────────────────┘                   │
│                                                                          │
│  Storage Limits:                                                        │
│  • Max message age: 7 days (configurable)                              │
│  • Max storage per user: 10 MB                                         │
│  • Auto-delete on retrieval                                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Notification Hints

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Notification Hint Structure                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  typedef struct {                                                       │
│      uint8_t recipient_id[32];  /* Who the message is for */           │
│      uint8_t storage_id[8];     /* CyxCloud storage ID */              │
│      uint64_t timestamp;        /* When stored */                       │
│      uint32_t ttl;              /* Time-to-live (seconds) */           │
│      uint8_t sender_hint[4];    /* First 4 bytes of sender ID */       │
│  } cyxchat_notification_hint_t; /* 56 bytes */                          │
│                                                                          │
│  Privacy considerations:                                                │
│  • Full sender ID not stored (prevents relay from knowing full graph)   │
│  • 4-byte hint allows recipient to identify sender locally              │
│  • Storage ID is opaque (relay can't read content)                     │
│  • TTL prevents indefinite storage                                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Group Chat

### Group Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Group Chat Architecture                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Group Structure:                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  group_id:     Random 8-byte identifier                          │   │
│  │  group_key:    Symmetric key for group encryption                │   │
│  │  creator:      Node ID of group creator                          │   │
│  │  admins[]:     List of admin node IDs                            │   │
│  │  members[]:    List of member node IDs                           │   │
│  │  name:         Human-readable group name                          │   │
│  │  created_at:   Creation timestamp                                 │   │
│  │  key_version:  Increments on each key rotation                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Limits:                                                                │
│  • Max members: 50 (due to O(N) message distribution)                  │
│  • Max admins: 5                                                        │
│  • Max name length: 64 bytes                                            │
│                                                                          │
│  Message Distribution:                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │  Sender ──┬──► Member1 (onion routed)                           │   │
│  │           ├──► Member2 (onion routed)                           │   │
│  │           ├──► Member3 (onion routed)                           │   │
│  │           ├──► ...                                               │   │
│  │           └──► MemberN (onion routed)                           │   │
│  │                                                                  │   │
│  │  Each message sent N times (once per member)                    │   │
│  │  Each route independent (privacy preserved)                     │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Group Key Management

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Group Key Management                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Key Derivation:                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  master_secret = random(32)                                      │   │
│  │  group_key = HKDF(master_secret, "cyxchat-group-v1", version)   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Key Rotation (when to rotate):                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Member joins: New key excludes ability to read old messages  │   │
│  │  • Member leaves: New key excludes departed member              │   │
│  │  • Monthly: Scheduled rotation for forward secrecy              │   │
│  │  • Admin request: Manual rotation if compromise suspected       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Key Distribution:                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Admin generates new_master_secret                            │   │
│  │  2. For each member:                                             │   │
│  │     encrypted_key = Encrypt(new_master_secret, member_pubkey)   │   │
│  │     send(CHAT_KEY_UPDATE, encrypted_key)                        │   │
│  │  3. Members decrypt and derive new group_key                    │   │
│  │  4. Increment key_version                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Forward Secrecy:                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Old keys are deleted after rotation                           │   │
│  │  • Cannot decrypt messages from before you joined               │   │
│  │  • Cannot decrypt messages after you leave (after rotation)     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Group Operations

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Group Operations                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Create Group:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Generate group_id = random(8)                                │   │
│  │  2. Generate master_secret = random(32)                          │   │
│  │  3. Set creator = self                                           │   │
│  │  4. Add self to members[] and admins[]                          │   │
│  │  5. Store locally                                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Invite Member (admin only):                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Encrypt master_secret with invitee's public key             │   │
│  │  2. Send CHAT_GROUP_INVITE with group_id, encrypted_key, name   │   │
│  │  3. Wait for CHAT_GROUP_JOIN acknowledgment                     │   │
│  │  4. Add to members[], broadcast member list update              │   │
│  │  5. Rotate key (so new member can't read old messages)          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Remove Member (admin only):                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Remove from members[]                                        │   │
│  │  2. Rotate group key (exclude removed member)                   │   │
│  │  3. Broadcast updated member list                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Leave Group (any member):                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Send CHAT_GROUP_LEAVE to all members                        │   │
│  │  2. Delete local group data and keys                            │   │
│  │  3. Admins will rotate key for remaining members                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Promote Admin (creator only):                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Add member to admins[]                                       │   │
│  │  2. Broadcast updated admin list                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## File Sharing

### Small Files (Direct Transfer)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Small File Transfer (≤768 bytes)                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Constraint: Max chunk = 48 bytes, max chunks = 16                      │
│  Max direct transfer = 48 × 16 = 768 bytes                              │
│                                                                          │
│  Send Flow:                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Generate file_id = random(8)                                 │   │
│  │  2. Calculate total_chunks = ceil(file_size / 48)               │   │
│  │  3. Send CHAT_FILE_META with filename, size                      │   │
│  │  4. For each chunk:                                              │   │
│  │     send(CHAT_FILE_CHUNK, file_id, chunk_index, data)           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Receive Flow:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Receive FILE_META, allocate buffer                          │   │
│  │  2. Collect chunks as they arrive                               │   │
│  │  3. When all chunks received:                                    │   │
│  │     - Verify MAC                                                 │   │
│  │     - Save to disk                                               │   │
│  │     - Send ACK                                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Chunk Retransmission:                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Timeout per chunk: 10 seconds                                 │   │
│  │  • Max retries: 3                                                │   │
│  │  • Receiver can request specific missing chunks                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Large Files (CyxCloud Storage)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Large File Transfer (>768 bytes)                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Send Flow:                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Generate file_key = random(32)                               │   │
│  │  2. Encrypt file: encrypted = XChaCha20Poly1305(file, file_key) │   │
│  │  3. Store in CyxCloud: storage_id = cyxcloud.store(encrypted)   │   │
│  │  4. Send FILE_META with storage_id, file_key, filename, size    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Receive Flow:                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Receive FILE_META                                            │   │
│  │  2. Retrieve from CyxCloud: encrypted = cyxcloud.get(storage_id)│   │
│  │  3. Decrypt: file = Decrypt(encrypted, file_key)                │   │
│  │  4. Verify integrity (MAC in ciphertext)                        │   │
│  │  5. Save to disk                                                 │   │
│  │  6. Send ACK                                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  File Size Limits:                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Recommended max: 100 MB (mesh network consideration)          │   │
│  │  • Absolute max: 1 GB                                            │   │
│  │  • Large files chunked in CyxCloud (64 KB chunks)               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Thumbnail Generation:                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  For images:                                                     │   │
│  │  • Generate 64x64 thumbnail                                      │   │
│  │  • Compress to ~500 bytes                                        │   │
│  │  • Include in FILE_META as preview                              │   │
│  │  • Recipient sees preview before downloading full image         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Voice Messages

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Voice Messages                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Recording:                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Format: Opus codec (best compression)                         │   │
│  │  • Bitrate: 16 kbps (speech optimized)                          │   │
│  │  • Sample rate: 24 kHz                                           │   │
│  │  • Max duration: 5 minutes (at 16kbps ≈ 600 KB)                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Waveform Preview:                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Generate visual waveform (100 samples)                       │   │
│  │  • Include in FILE_META (100 bytes)                             │   │
│  │  • Display before playback                                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Playback:                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Stream from CyxCloud (for large files)                       │   │
│  │  • Buffer 5 seconds ahead                                        │   │
│  │  • Variable speed playback (0.5x - 2x)                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Security Model

### Encryption Stack

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Encryption Stack                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Layer           │ Algorithm              │ Purpose              │   │
│  │  ────────────────┼────────────────────────┼────────────────────  │   │
│  │  Key Exchange    │ X25519                 │ Establish shared key │   │
│  │  Key Derivation  │ HKDF-SHA256            │ Derive session keys  │   │
│  │  Message Encrypt │ XChaCha20-Poly1305     │ Content encryption   │   │
│  │  Onion Layers    │ XChaCha20-Poly1305     │ Route encryption     │   │
│  │  File Encrypt    │ XChaCha20-Poly1305     │ File confidentiality │   │
│  │  Group Encrypt   │ XChaCha20-Poly1305     │ Group messages       │   │
│  │  Storage         │ K-of-N Shamir          │ Distributed trust    │   │
│  │  Hashing         │ BLAKE2b                │ Message IDs, MACs    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Why XChaCha20-Poly1305?                                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • 24-byte nonce (safe with random nonces)                       │   │
│  │  • No timing attacks (constant-time implementation)             │   │
│  │  • AEAD (authenticated encryption with associated data)         │   │
│  │  • libsodium provides optimized implementation                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Threat Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Threat Model                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Threat                │ Mitigation                                     │
│  ──────────────────────┼───────────────────────────────────────────────│
│  Eavesdropping         │ E2E encryption (XChaCha20-Poly1305)           │
│  Man-in-the-middle     │ X25519 key exchange, safety numbers           │
│  Traffic analysis      │ Onion routing (3 hops), padding               │
│  Metadata collection   │ No central server, onion routing              │
│  Compromised relay     │ K-of-N storage, multiple hops                 │
│  Device seizure        │ Local encryption, secure delete               │
│  Key compromise        │ Hourly key rotation, forward secrecy          │
│  Spam/abuse            │ Reputation system, rate limiting              │
│  Sybil attack          │ Stake requirement, challenge responses        │
│  Replay attack         │ Timestamps, message IDs, nonces               │
│  Denial of service     │ Rate limiting, connection caps                │
│                                                                          │
│  Trust Assumptions:                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. Libsodium cryptographic primitives are secure               │   │
│  │  2. At least 1 of 3 onion hops is honest                        │   │
│  │  3. K-of-N storage providers are not all colluding              │   │
│  │  4. User's device is not compromised at time of use             │   │
│  │  5. Random number generator is secure                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Rotation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Key Rotation Schedule                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Key Type              │ Rotation Period │ Trigger                      │
│  ──────────────────────┼─────────────────┼──────────────────────────────│
│  X25519 keypair        │ 1 hour          │ Timer, re-announce to peers  │
│  Session keys          │ Per-message     │ Derived from DH + nonce      │
│  Group keys            │ On change       │ Member join/leave/monthly    │
│  File keys             │ Per-file        │ Random per file              │
│  MPC MAC keys          │ 1 hour          │ Timer, automatic             │
│                                                                          │
│  Forward Secrecy Properties:                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Compromise of current key doesn't reveal past messages       │   │
│  │  • Old keys are securely deleted                                │   │
│  │  • New keys cannot decrypt old ciphertext                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## UI/UX Design

### Screen Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Screen Hierarchy                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  App Launch                                                             │
│  ├── First Launch                                                       │
│  │   ├── Welcome Screen                                                 │
│  │   ├── Create Identity                                                │
│  │   ├── Set Display Name (optional)                                   │
│  │   └── Backup Recovery Phrase (recommended)                          │
│  │                                                                      │
│  └── Main App                                                           │
│      ├── Chat List (Home)                                              │
│      │   ├── Search chats                                              │
│      │   ├── Start new chat                                            │
│      │   └── Create group                                              │
│      │                                                                  │
│      ├── Chat Detail                                                   │
│      │   ├── Message list                                              │
│      │   ├── Message input                                             │
│      │   ├── Attachments (file, voice, camera)                        │
│      │   └── Chat info/settings                                        │
│      │                                                                  │
│      ├── Contacts                                                       │
│      │   ├── Contact list                                              │
│      │   ├── Add contact (QR, link, search)                           │
│      │   └── Contact detail                                            │
│      │                                                                  │
│      ├── Profile                                                        │
│      │   ├── My QR code                                                │
│      │   ├── Display name                                              │
│      │   ├── Node ID                                                   │
│      │   └── Recovery phrase                                           │
│      │                                                                  │
│      └── Settings                                                       │
│          ├── Privacy                                                   │
│          │   ├── Read receipts                                         │
│          │   ├── Typing indicators                                     │
│          │   └── Online status                                         │
│          ├── Notifications                                             │
│          ├── Network                                                   │
│          │   ├── Transport selection                                   │
│          │   ├── Bootstrap servers                                     │
│          │   └── Relay preferences                                     │
│          ├── Storage                                                   │
│          │   ├── Message retention                                     │
│          │   └── Clear data                                            │
│          └── About                                                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Chat List Screen

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Chat List Screen                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  CyxChat                                    [Search] [+]        │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  ┌───┐  Alice                              2m ago               │   │
│  │  │ A │  Thanks for the file! ●●                                │   │
│  │  └───┘                                                          │   │
│  │  ─────────────────────────────────────────────────────────────  │   │
│  │  ┌───┐  Project Team (5)                   15m ago              │   │
│  │  │ PT│  Bob: Meeting at 3pm ●              (3)                 │   │
│  │  └───┘                                                          │   │
│  │  ─────────────────────────────────────────────────────────────  │   │
│  │  ┌───┐  Charlie                            1h ago               │   │
│  │  │ C │  🎤 Voice message (0:42) ●                               │   │
│  │  └───┘                                                          │   │
│  │  ─────────────────────────────────────────────────────────────  │   │
│  │  ┌───┐  Diana                              Yesterday            │   │
│  │  │ D │  Sounds good!                                            │   │
│  │  └───┘                                                          │   │
│  │                                                                  │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │  [Chats]    [Contacts]    [Profile]    [Settings]              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Status Indicators:                                                     │
│  • ○  Sending                                                          │
│  • ◐  Sent to network                                                  │
│  • ●  Delivered                                                        │
│  • ●● Read                                                             │
│  • (3) Unread count badge                                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Chat Detail Screen

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Chat Detail Screen                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  ← Alice                                   🔒 Encrypted         │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │                              ┌────────────────────┐             │   │
│  │                              │ Hey! How are you?  │  10:30 ●●   │   │
│  │                              └────────────────────┘             │   │
│  │                                                                  │   │
│  │  ┌────────────────────┐                                         │   │
│  │  │ I'm good, thanks!  │  10:32 ●●                               │   │
│  │  └────────────────────┘                                         │   │
│  │                                                                  │   │
│  │                              ┌────────────────────┐             │   │
│  │                              │ Check out this     │             │   │
│  │                              │ ┌──────────────┐   │  10:35 ●●   │   │
│  │                              │ │ 📄 report.pdf│   │             │   │
│  │                              │ │    2.3 MB    │   │             │   │
│  │                              │ └──────────────┘   │             │   │
│  │                              └────────────────────┘             │   │
│  │                                                                  │   │
│  │  ┌────────────────────┐                                         │   │
│  │  │ Thanks for the     │  10:36 ●●                               │   │
│  │  │ file!              │                                         │   │
│  │  └────────────────────┘                                         │   │
│  │                                                                  │   │
│  │                                          Alice is typing...     │   │
│  │                                                                  │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │  [📎] [🎤] │ Type a message...                        │ [Send] │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Add Contact Screen

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Add Contact Screen                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  ← Add Contact                                                   │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │                                                          │    │   │
│  │  │      📷  Scan QR Code                                    │    │   │
│  │  │                                                          │    │   │
│  │  │  Point camera at contact's QR code                      │    │   │
│  │  │                                                          │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                  │   │
│  │  ─────────────────── OR ───────────────────                     │   │
│  │                                                                  │   │
│  │  Enter Node ID manually:                                        │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │ a1b2c3d4e5f6...                                          │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                    [Add]        │   │
│  │                                                                  │   │
│  │  ─────────────────── OR ───────────────────                     │   │
│  │                                                                  │   │
│  │  Search directory (public profiles only):                       │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │ 🔍 Search by username...                                 │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Cross-Platform Implementation

### Technology Stack

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Technology Stack                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Component         │ Technology               │ Notes                   │
│  ──────────────────┼──────────────────────────┼─────────────────────────│
│  UI Framework      │ Flutter (Dart)           │ Single codebase for all │
│  Core Protocol     │ C library (libcyxwiz)    │ Existing codebase       │
│  FFI Bridge        │ dart:ffi                 │ C ↔ Dart interop        │
│  Local Database    │ SQLite (sqlcipher)       │ Encrypted at rest       │
│  Key Storage       │ Platform keychain        │ Secure enclave          │
│  State Management  │ Riverpod                 │ Reactive state          │
│  Routing           │ go_router                │ Declarative routing     │
│  QR Code           │ mobile_scanner           │ Camera QR scanning      │
│  Notifications     │ flutter_local_notif      │ Local notifications     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### FFI Bridge Design

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      FFI Bridge Architecture                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Dart Side                        │ C Side                              │
│  ─────────────────────────────────┼───────────────────────────────────  │
│                                   │                                     │
│  // Generated bindings            │ // Header file                      │
│  class CyxwizBindings {           │ typedef struct {                    │
│    late Pointer<NativeType> ctx;  │   uint8_t node_id[32];             │
│                                   │   void* internal;                   │
│    void init() => ...             │ } cyxchat_ctx_t;                   │
│    void send(msg) => ...          │                                     │
│    Stream<Msg> receive() => ...   │ int cyxchat_init(ctx*);            │
│  }                                │ int cyxchat_send(ctx*, msg*);      │
│                                   │ int cyxchat_poll(ctx*, msg*, ms);  │
│  // High-level wrapper            │                                     │
│  class CyxChat {                  │                                     │
│    final _bindings = Cyxwiz...(); │                                     │
│                                   │                                     │
│    Future<void> sendMessage(      │                                     │
│      String to, String text       │                                     │
│    ) async { ... }                │                                     │
│  }                                │                                     │
│                                                                          │
│  Threading Model:                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Main Isolate (UI)                                               │   │
│  │  ├── User interactions                                           │   │
│  │  ├── State updates                                               │   │
│  │  └── Render                                                      │   │
│  │                                                                  │   │
│  │  Background Isolate (FFI)                                        │   │
│  │  ├── libcyxwiz event loop                                       │   │
│  │  ├── Network I/O                                                 │   │
│  │  └── Crypto operations                                           │   │
│  │                                                                  │   │
│  │  Communication: SendPort/ReceivePort (message passing)          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Platform-Specific Notes

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Platform-Specific Implementation                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Windows                                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Transport: UDP (primary), WiFi Direct, Bluetooth             │   │
│  │  • Storage: AppData\Roaming\CyxChat                             │   │
│  │  • Keys: Windows Credential Manager                             │   │
│  │  • Notifications: Windows Toast                                  │   │
│  │  • Build: MSVC + libsodium (vcpkg)                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  macOS                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Transport: UDP (primary), WiFi Direct, Bluetooth             │   │
│  │  • Storage: ~/Library/Application Support/CyxChat               │   │
│  │  • Keys: Keychain Services                                       │   │
│  │  • Notifications: UserNotifications framework                   │   │
│  │  • Build: Clang + libsodium (homebrew)                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Linux                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Transport: UDP (primary), WiFi Direct (wpa_supplicant), BT   │   │
│  │  • Storage: ~/.local/share/cyxchat                              │   │
│  │  • Keys: libsecret / GNOME Keyring                              │   │
│  │  • Notifications: D-Bus (org.freedesktop.Notifications)         │   │
│  │  • Build: GCC + libsodium (apt)                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  iOS                                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Transport: UDP (primary), Bluetooth LE                       │   │
│  │  • Storage: Documents directory (encrypted)                     │   │
│  │  • Keys: Keychain Services (Secure Enclave)                     │   │
│  │  • Notifications: APNs (optional, for background)               │   │
│  │  • Note: No WiFi Direct on iOS                                  │   │
│  │  • Build: Xcode + libsodium (CocoaPods)                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Android                                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Transport: UDP (primary), WiFi Direct, Bluetooth             │   │
│  │  • Storage: Internal storage (encrypted)                        │   │
│  │  • Keys: Android Keystore (hardware-backed)                     │   │
│  │  • Notifications: FCM (optional) or local                       │   │
│  │  • Build: NDK + libsodium                                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### Local Storage (SQLite)

```sql
-- Identity (single row)
CREATE TABLE identity (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    node_id BLOB NOT NULL,              -- 32 bytes
    public_key BLOB NOT NULL,           -- 32 bytes
    private_key_encrypted BLOB NOT NULL, -- Encrypted with device key
    display_name TEXT,
    avatar_path TEXT,
    created_at INTEGER NOT NULL,
    key_version INTEGER DEFAULT 1
);

-- Contacts
CREATE TABLE contacts (
    node_id BLOB PRIMARY KEY,           -- 32 bytes
    public_key BLOB NOT NULL,           -- 32 bytes
    display_name TEXT,
    avatar_path TEXT,
    verified INTEGER DEFAULT 0,         -- Key verification status
    blocked INTEGER DEFAULT 0,
    added_at INTEGER NOT NULL,
    last_seen INTEGER
);

-- Conversations
CREATE TABLE conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type INTEGER NOT NULL,              -- 0=direct, 1=group
    peer_id BLOB,                       -- For direct chats
    group_id BLOB,                      -- For groups
    name TEXT,
    last_message_id INTEGER,
    unread_count INTEGER DEFAULT 0,
    muted INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (peer_id) REFERENCES contacts(node_id)
);

-- Messages
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL,
    msg_id BLOB NOT NULL UNIQUE,        -- 8-byte message ID
    sender_id BLOB NOT NULL,            -- 32-byte node ID
    type INTEGER NOT NULL,              -- Message type
    content BLOB,                       -- Encrypted content
    status INTEGER DEFAULT 0,           -- 0=sending, 1=sent, 2=delivered, 3=read
    created_at INTEGER NOT NULL,
    delivered_at INTEGER,
    read_at INTEGER,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

-- Groups
CREATE TABLE groups (
    group_id BLOB PRIMARY KEY,          -- 8 bytes
    name TEXT NOT NULL,
    creator_id BLOB NOT NULL,
    group_key_encrypted BLOB NOT NULL,  -- Encrypted master secret
    key_version INTEGER DEFAULT 1,
    created_at INTEGER NOT NULL
);

-- Group members
CREATE TABLE group_members (
    group_id BLOB NOT NULL,
    member_id BLOB NOT NULL,
    is_admin INTEGER DEFAULT 0,
    joined_at INTEGER NOT NULL,
    PRIMARY KEY (group_id, member_id),
    FOREIGN KEY (group_id) REFERENCES groups(group_id)
);

-- Pending files (incomplete transfers)
CREATE TABLE pending_files (
    file_id BLOB PRIMARY KEY,           -- 8 bytes
    conversation_id INTEGER NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    total_chunks INTEGER NOT NULL,
    received_chunks INTEGER DEFAULT 0,
    chunks_data BLOB,                   -- Temporary chunk storage
    created_at INTEGER NOT NULL,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

-- Offline message hints (to check on startup)
CREATE TABLE offline_hints (
    storage_id BLOB PRIMARY KEY,        -- 8 bytes
    sender_hint BLOB NOT NULL,          -- 4 bytes
    timestamp INTEGER NOT NULL,
    retrieved INTEGER DEFAULT 0
);

-- Indexes
CREATE INDEX idx_messages_conversation ON messages(conversation_id);
CREATE INDEX idx_messages_timestamp ON messages(created_at);
CREATE INDEX idx_conversations_updated ON conversations(updated_at);
CREATE INDEX idx_group_members_member ON group_members(member_id);
```

---

## Error Handling

### Error Codes

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CyxChat Error Codes                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Code    │ Name                    │ Description                        │
│  ────────┼─────────────────────────┼────────────────────────────────────│
│  0       │ CYXCHAT_OK              │ Success                            │
│  1       │ CYXCHAT_ERR_NETWORK     │ Network unreachable                │
│  2       │ CYXCHAT_ERR_TIMEOUT     │ Operation timed out                │
│  3       │ CYXCHAT_ERR_OFFLINE     │ Recipient is offline               │
│  4       │ CYXCHAT_ERR_CRYPTO      │ Cryptographic error                │
│  5       │ CYXCHAT_ERR_INVALID_KEY │ Invalid or expired key             │
│  6       │ CYXCHAT_ERR_NO_ROUTE    │ No route to destination            │
│  7       │ CYXCHAT_ERR_STORAGE     │ Storage operation failed           │
│  8       │ CYXCHAT_ERR_BLOCKED     │ Contact is blocked                 │
│  9       │ CYXCHAT_ERR_GROUP_FULL  │ Group member limit reached         │
│  10      │ CYXCHAT_ERR_NOT_ADMIN   │ Admin privileges required          │
│  11      │ CYXCHAT_ERR_FILE_SIZE   │ File too large                     │
│  12      │ CYXCHAT_ERR_RATE_LIMIT  │ Rate limit exceeded                │
│  13      │ CYXCHAT_ERR_INVALID_MSG │ Invalid message format             │
│  14      │ CYXCHAT_ERR_DUPLICATE   │ Duplicate message ID               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Retry Logic

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Message Retry Logic                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Direct Message Retry:                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Attempt 1: Immediate send                                       │   │
│  │  Attempt 2: Wait 5 seconds                                       │   │
│  │  Attempt 3: Wait 15 seconds                                      │   │
│  │  Attempt 4: Wait 60 seconds                                      │   │
│  │  After 4 failures: Store in CyxCloud for offline delivery       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  File Chunk Retry:                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Timeout per chunk: 10 seconds                                   │   │
│  │  Max retries per chunk: 3                                        │   │
│  │  After 3 failures: Mark transfer as failed                      │   │
│  │  User can manually retry entire transfer                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Group Message Retry:                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Each member is independent                                      │   │
│  │  Failed members: Store for offline delivery                     │   │
│  │  Successful members: Continue immediately                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Rate Limiting

### Client-Side Limits

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Rate Limits                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Operation              │ Limit          │ Window      │ Enforcement    │
│  ───────────────────────┼────────────────┼─────────────┼────────────────│
│  Send message           │ 30/minute      │ 1 minute    │ Queue excess   │
│  Send to same contact   │ 10/minute      │ 1 minute    │ Delay          │
│  Typing indicator       │ 1/3 seconds    │ Per contact │ Throttle       │
│  File transfer          │ 5 concurrent   │ Global      │ Queue          │
│  Group creation         │ 5/day          │ 24 hours    │ Reject         │
│  Contact add            │ 20/hour        │ 1 hour      │ Reject         │
│  Key rotation           │ 1/hour         │ Per contact │ Skip           │
│                                                                          │
│  Anti-Spam Measures:                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • New contacts: Limited to 5 messages until reply received     │   │
│  │  • Reputation check: Low-reputation peers throttled            │   │
│  │  • Content filtering: Optional client-side spam detection      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Testing Strategy

### Test Categories

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Testing Strategy                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Unit Tests (C library):                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Message serialization/deserialization                        │   │
│  │  • Encryption/decryption                                        │   │
│  │  • Key derivation                                               │   │
│  │  • Fragment assembly                                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Integration Tests:                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • End-to-end message delivery (2 nodes)                        │   │
│  │  • Onion routing (4+ nodes)                                     │   │
│  │  • Offline message storage/retrieval                            │   │
│  │  • Group message distribution                                   │   │
│  │  • File transfer (small and large)                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Flutter Widget Tests:                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Chat list rendering                                          │   │
│  │  • Message bubble display                                       │   │
│  │  • Contact management UI                                        │   │
│  │  • Settings screens                                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  E2E Tests (Flutter integration):                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Full app flow: create identity → add contact → send message  │   │
│  │  • Group creation and messaging                                 │   │
│  │  • File sharing workflow                                        │   │
│  │  • Offline/online transition                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Performance Tests:                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Message latency (target: <500ms local, <2s global)           │   │
│  │  • Throughput (target: 30 msg/min sustained)                   │   │
│  │  • Memory usage (target: <100MB active)                         │   │
│  │  • Battery usage (target: <5% per hour active)                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Core Messaging
- Define message structs in C (chat.h)
- Implement CHAT_MSG send/receive
- Implement CHAT_ACK delivery confirmation
- Basic Flutter UI (chat list, chat detail)
- FFI bridge for core functions
- SQLite database setup

### Phase 2: User Experience
- Contact management (add, remove, block)
- QR code generation/scanning
- Presence indicators (online/offline)
- Read receipts
- Typing indicators
- Key verification (safety numbers)

### Phase 3: Group Chat
- Group creation flow
- Group key management
- Member invite/remove
- Group message routing
- Admin permissions
- Key rotation on member changes

### Phase 4: Rich Features
- Small file sharing (direct transfer)
- Large file sharing (CyxCloud integration)
- Voice messages (Opus encoding)
- Image thumbnails
- Offline message storage and retrieval

### Phase 5: Polish
- Platform-specific notifications
- Settings and preferences
- Theme support (dark/light)
- Accessibility (screen readers)
- Performance optimization
- Battery optimization

---

## Appendix: Protocol Constants

```c
/* CyxChat Protocol Constants */

/* Message types (0x10-0x1F range) */
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

/* Size limits */
#define CYXCHAT_MAX_TEXT_LEN     28    /* Per-packet text (3-hop onion) */
#define CYXCHAT_MAX_CHUNK_SIZE   48    /* File chunk size */
#define CYXCHAT_MAX_CHUNKS       16    /* Max chunks per file (direct) */
#define CYXCHAT_MAX_DIRECT_FILE  768   /* Max direct file transfer */
#define CYXCHAT_MAX_GROUP_MEMBERS 50   /* Max members per group */
#define CYXCHAT_MAX_GROUP_NAME   64    /* Max group name length */

/* Timeouts (milliseconds) */
#define CYXCHAT_ACK_TIMEOUT_MS      10000  /* Wait for ACK */
#define CYXCHAT_CHUNK_TIMEOUT_MS    10000  /* Wait for chunk ACK */
#define CYXCHAT_TYPING_TIMEOUT_MS   3000   /* Typing indicator expiry */
#define CYXCHAT_PRESENCE_TIMEOUT_MS 60000  /* Presence update interval */
#define CYXCHAT_OFFLINE_STORAGE_TTL 604800 /* 7 days in seconds */

/* Retry limits */
#define CYXCHAT_MAX_MSG_RETRIES     4
#define CYXCHAT_MAX_CHUNK_RETRIES   3

/* Presence status */
#define CYXCHAT_PRESENCE_OFFLINE 0
#define CYXCHAT_PRESENCE_ONLINE  1
#define CYXCHAT_PRESENCE_AWAY    2
#define CYXCHAT_PRESENCE_BUSY    3

/* Message status */
#define CYXCHAT_STATUS_SENDING   0
#define CYXCHAT_STATUS_SENT      1
#define CYXCHAT_STATUS_DELIVERED 2
#define CYXCHAT_STATUS_READ      3
#define CYXCHAT_STATUS_FAILED    4
```

---

## Summary

CyxChat is designed to be:

1. **Private by default** - No accounts, no phone numbers, full encryption
2. **Decentralized** - No central servers, mesh network resilience
3. **Cross-platform** - Single Flutter codebase, native C performance
4. **Offline capable** - Messages queue and sync automatically
5. **Feature complete** - Direct chat, groups, files, voice messages
6. **Standards compliant** - Uses proven cryptographic primitives

The design leverages the existing CyxWiz infrastructure (onion routing, CyxCloud storage, reputation system) to provide a complete messaging solution that prioritizes user privacy and network resilience.
