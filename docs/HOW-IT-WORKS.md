# How CyxChat Works: Messaging & File Transfer

A deep dive into how CyxChat achieves secure, decentralized communication.

---

## Table of Contents

1. [Messaging System](#messaging-system)
2. [File Transfer System](#file-transfer-system)
3. [Security Architecture](#security-architecture)
4. [Why We're More Secure](#why-were-more-secure)

---

## Messaging System

### The Big Picture

Traditional messengers route everything through central servers. CyxChat establishes direct peer-to-peer connections, with messages wrapped in multiple layers of encryption.

```
TRADITIONAL (WhatsApp, Signal, etc.)
================================

  Alice                   Server                    Bob
    │                       │                        │
    │──── Message ─────────>│                        │
    │                       │────── Message ────────>│
    │                       │                        │
    │    Server sees:       │                        │
    │    - Who talks to who │                        │
    │    - When they talk   │                        │
    │    - Message sizes    │                        │


CYXCHAT (Peer-to-Peer)
================================

  Alice ◄─────────────────────────────────────────► Bob
                     Direct Connection
                   (or via relay if needed)

    No server sees metadata. Even relay can't read content.
```

### Message Flow: Sending

When you send a message, here's what happens:

```
┌─────────────────────────────────────────────────────────────────┐
│                        SENDER SIDE                               │
└─────────────────────────────────────────────────────────────────┘

    Your Message: "Hello Bob!"
           │
           ▼
    ┌──────────────────┐
    │  1. SERIALIZE    │   Convert to compact wire format
    │                  │   [type|flags|msg_id|text_len|text]
    │  10 bytes header │   Total: 16 bytes for "Hello Bob!"
    │  + payload       │
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  2. ENCRYPT      │   XChaCha20-Poly1305
    │                  │
    │  Per-hop keys    │   Each relay only decrypts its layer
    │  from X25519 DH  │   revealing only the NEXT hop
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  3. ONION WRAP   │   Layer encryption like an onion
    │                  │
    │  Bob's layer     │   ┌──────────────────────┐
    │  (innermost)     │   │ ┌──────────────────┐ │
    │                  │   │ │ ┌──────────────┐ │ │
    │  Relay's layer   │   │ │ │   Message    │ │ │
    │  (outer)         │   │ │ │  "Hello!"    │ │ │
    │                  │   │ │ └──────────────┘ │ │
    │                  │   │ │  Bob's Layer     │ │
    │                  │   │ └──────────────────┘ │
    │                  │   │   Relay's Layer      │
    │                  │   └──────────────────────┘
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  4. TRANSPORT    │   UDP packet sent
    │                  │
    │  Direct P2P      │   If direct: Alice → Bob
    │  or via Relay    │   If relay:  Alice → Relay → Bob
    └──────────────────┘
```

### Message Flow: Receiving

```
┌─────────────────────────────────────────────────────────────────┐
│                       RECEIVER SIDE                              │
└─────────────────────────────────────────────────────────────────┘

    Encrypted Packet Arrives
           │
           ▼
    ┌──────────────────┐
    │  1. ONION PEEL   │   Decrypt outer layer
    │                  │   Check: Is this for me?
    │  X25519 + shared │
    │  secret decrypt  │   Yes → Continue to step 2
    │                  │   No  → Forward to next hop
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  2. DECRYPT      │   XChaCha20-Poly1305 (AEAD cipher)
    │                  │
    │  Verify Poly1305 │   The 16-byte authentication tag proves:
    │  auth tag        │   • Data wasn't tampered with (integrity)
    │                  │   • Sender had the correct key (authenticity)
    │                  │
    │                  │   If tag fails → Drop (tampered/wrong key)
    │                  │   If tag valid → Extract plaintext
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  3. PARSE        │   Extract wire format
    │                  │
    │  type: TEXT      │   Message type identifier
    │  flags: 0x03     │   ENCRYPTED | NO_STORE
    │  msg_id: abc123  │   Unique message ID
    │  text: "Hello!"  │   Your message content
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  4. QUEUE        │   Ring buffer (32 messages)
    │                  │
    │  FFI polling     │   Dart polls: cyxchat_recv_next()
    │  retrieves msg   │   Message delivered to UI
    └──────────────────┘
```

### Message Fragmentation

Messages over 80 bytes are split into fragments:

```
Original Message (200 bytes):
"Lorem ipsum dolor sit amet, consectetur adipiscing elit.
 Sed do eiusmod tempor incididunt ut labore et dolore magna
 aliqua. Ut enim ad minim veniam..."

                    │
                    ▼ FRAGMENTATION

┌─────────────────────────────────────────────────────────────┐
│ Fragment 0/3     │ Fragment 1/3     │ Fragment 2/3          │
│ [msg_id][0][3]   │ [msg_id][1][3]   │ [msg_id][2][3]        │
│ "Lorem ipsum..." │ "...adipiscing.."│ "...ad minim..."      │
│ (80 bytes)       │ (80 bytes)       │ (40 bytes)            │
└─────────────────────────────────────────────────────────────┘
         │                  │                  │
         └──────────────────┼──────────────────┘
                           ▼
                    REASSEMBLY BUFFER
                    (30 second timeout)
                           │
                           ▼
                    Complete Message
                    "Lorem ipsum..."
```

### Wire Format Details

```
TEXT MESSAGE (compact binary format)
====================================

Byte:  0      1       2-9        10        11-N
     ┌────┬───────┬──────────┬──────────┬────────────┐
     │Type│ Flags │  Msg ID  │ Text Len │    Text    │
     │0x10│  0x03 │ 8 bytes  │  1 byte  │  N bytes   │
     └────┴───────┴──────────┴──────────┴────────────┘

Flags:
  Bit 0: ENCRYPTED     (always set)
  Bit 1: NO_STORE      (don't persist)
  Bit 2: FRAGMENTED    (part of larger message)
  Bit 3: REPLY         (replying to another msg)

FRAGMENTED MESSAGE
==================

Byte:  0      1       2-9       10       11        12        13-N
     ┌────┬───────┬──────────┬────────┬──────────┬──────────┬────────┐
     │Type│ Flags │  Msg ID  │Frag Idx│Tot Frags │ Text Len │  Text  │
     │0x10│  0x07 │ 8 bytes  │ 1 byte │  1 byte  │  1 byte  │N bytes │
     └────┴───────┴──────────┴────────┴──────────┴──────────┴────────┘
```

---

## File Transfer System

### Overview

Files are transferred in small chunks that fit within the onion routing payload limits. Each chunk is individually encrypted and verified.

```
FILE TRANSFER CONSTRAINTS
=========================

LoRa packet limit:     250 bytes max
Onion overhead:        40 bytes/layer (nonce + auth tag)
1-hop payload:         ~139 bytes usable
Chunk overhead:        13 bytes (type + file_id + idx + len)
─────────────────────────────────────────────────────────
Safe chunk size:       90 bytes (tested limit)

For a 64KB file:
  64,000 ÷ 90 = 712 chunks
  712 × 250ms delay = ~3 minutes transfer time
```

### File Transfer Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    FILE TRANSFER: SENDING                        │
└─────────────────────────────────────────────────────────────────┘

    User selects: photo.jpg (5,400 bytes)
           │
           ▼
    ┌──────────────────┐
    │  1. HASH FILE    │   BLAKE2b hash of entire file
    │                  │   → Integrity verification
    │  file_hash =     │   → Recipient can verify
    │  blake2b(data)   │      nothing was corrupted
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  2. ENCRYPT      │   XChaCha20-Poly1305
    │     WHOLE FILE   │
    │                  │   24-byte random nonce
    │  encrypted_data  │   + 16-byte auth tag
    │  = encrypt(data) │   → Even relay can't peek
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  3. CALCULATE    │   5,400 ÷ 90 = 60 chunks
    │     CHUNKS       │
    │                  │   Last chunk may be smaller
    │  chunk_count=60  │   (5,400 mod 90 = 0 here)
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  4. SEND         │   Contains:
    │     FILE_META    │   - file_id (8 bytes, random)
    │                  │   - filename: "photo.jpg"
    │  One-time setup  │   - size: 5,400 bytes
    │  packet          │   - chunk_count: 60
    │                  │   - file_hash: 32 bytes
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────────────────────────────────────────┐
    │  5. SEND CHUNKS (with 250ms delay between each)      │
    │                                                      │
    │  Chunk 0   Chunk 1   Chunk 2         Chunk 59       │
    │  ┌─────┐   ┌─────┐   ┌─────┐   ...   ┌─────┐        │
    │  │90 B │   │90 B │   │90 B │         │90 B │        │
    │  └─────┘   └─────┘   └─────┘         └─────┘        │
    │     │         │         │               │           │
    │     └─────────┴─────────┴───────────────┘           │
    │                        │                            │
    │                        ▼                            │
    │              All wrapped in onion routing           │
    │              Each chunk encrypted TWICE:            │
    │              1. File encryption (outer)             │
    │              2. Onion encryption (transport)        │
    └──────────────────────────────────────────────────────┘
```

### Receiving Files

```
┌─────────────────────────────────────────────────────────────────┐
│                    FILE TRANSFER: RECEIVING                      │
└─────────────────────────────────────────────────────────────────┘

    FILE_META packet arrives
           │
           ▼
    ┌──────────────────┐
    │  1. ALLOCATE     │   Reserve memory for file
    │     BUFFERS      │
    │                  │   data_buffer[5,400]
    │  + bitmap for    │   chunk_bitmap[60 bits]
    │    tracking      │   (1 bit per chunk)
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  2. AUTO-ACCEPT  │   Files < 64KB accepted automatically
    │     (< 64KB)     │
    │                  │   Larger files would need UI prompt
    │  Start receiving │   (not implemented yet)
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────────────────────────────────────────┐
    │  3. RECEIVE CHUNKS                                   │
    │                                                      │
    │  For each FILE_CHUNK packet:                        │
    │                                                      │
    │    ┌─────────────────────────────────────────────┐  │
    │    │ a. Extract chunk_index, chunk_data         │  │
    │    │ b. Copy data to buffer at correct offset   │  │
    │    │    offset = chunk_index × 90               │  │
    │    │ c. Set bit in bitmap: chunk_bitmap[idx]=1  │  │
    │    │ d. Update progress: chunks_done++          │  │
    │    └─────────────────────────────────────────────┘  │
    │                                                      │
    │  Chunk bitmap visualization:                        │
    │  [1][1][1][1][0][1][1][0][0][0]...                  │
    │   ▲  ▲  ▲  ▲     ▲  ▲                              │
    │   │  │  │  │     │  │                              │
    │   received       still waiting                      │
    └──────────────────────────────────────────────────────┘
             │
             ▼
    ┌──────────────────┐
    │  4. ALL CHUNKS   │   Check: All bits in bitmap = 1?
    │     RECEIVED?    │
    │                  │   Yes → Continue
    │  bitmap all 1s   │   No  → Keep waiting (30s timeout)
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  5. DECRYPT      │   XChaCha20-Poly1305 decrypt
    │     FILE         │
    │                  │   Verify auth tag
    │  plaintext =     │   If fail → Corrupted, discard
    │  decrypt(data)   │
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  6. VERIFY       │   Compute BLAKE2b of decrypted data
    │     HASH         │
    │                  │   Compare with file_hash from META
    │  blake2b(plain)  │   Match → File intact
    │  == file_hash?   │   Mismatch → Tampered, discard
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  7. COMPLETE     │   Call onFileComplete callback
    │                  │
    │  File ready!     │   User can save to disk
    │                  │   Memory buffer cleared after
    └──────────────────┘
```

### Wire Format: File Transfer

```
FILE_META (sent once at start)
==============================

Byte:   0       1-8        9          10-N       N+1       N+2-M
      ┌─────┬──────────┬──────────┬──────────┬──────────┬──────────┐
      │Type │ File ID  │Fname Len │ Filename │ Mime Len │MIME Type │
      │0x14 │ 8 bytes  │  1 byte  │ variable │  1 byte  │ variable │
      └─────┴──────────┴──────────┴──────────┴──────────┴──────────┘

      continued...

      ┌──────────┬────────────┬────────────────────────────────────┐
      │  Size    │Chunk Count │          File Hash                 │
      │ 4 bytes  │  2 bytes   │          32 bytes                  │
      └──────────┴────────────┴────────────────────────────────────┘


FILE_CHUNK (sent for each piece)
================================

Byte:   0       1-8        9-10       11-12      13-N
      ┌─────┬──────────┬──────────┬──────────┬──────────────────┐
      │Type │ File ID  │Chunk Idx │Chunk Len │    Chunk Data    │
      │0x15 │ 8 bytes  │ 2 bytes  │ 2 bytes  │  up to 90 bytes  │
      └─────┴──────────┴──────────┴──────────┴──────────────────┘
```

---

## Security Architecture

### Encryption Layers

CyxChat uses multiple layers of encryption for defense in depth:

```
ENCRYPTION LAYER DIAGRAM
========================

                    ┌───────────────────────────────────────┐
                    │         Your Message                  │
                    │        "Hello Bob!"                   │
                    └───────────────────────────────────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────────────────────┐
        │  LAYER 1: Application Encryption (for files)            │
        │                                                         │
        │  Algorithm: XChaCha20-Poly1305 (AEAD)                   │
        │  Key:       Shared secret from X25519 key exchange      │
        │  Purpose:   Content confidentiality + integrity         │
        │  Overhead:  24 byte nonce + 16 byte auth tag = 40 bytes │
        │                                                         │
        │  AEAD = Authenticated Encryption with Associated Data   │
        │  • XChaCha20 encrypts the data (confidentiality)        │
        │  • Poly1305 computes a 16-byte authentication tag       │
        │    over the ciphertext (integrity + authenticity)       │
        │  • On decrypt: tag is verified FIRST, then decryption   │
        │    happens only if tag matches                          │
        └─────────────────────────────────────────────────────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────────────────────┐
        │  LAYER 2: Onion Routing (per-hop encryption)            │
        │                                                         │
        │  Algorithm: XChaCha20-Poly1305 per hop                  │
        │  Key:       Derived from X25519 DH with each relay      │
        │  Purpose:   Path anonymity - each hop only sees next    │
        │  Overhead:  40 bytes per hop                            │
        │                                                         │
        │  ┌─────────────────────────────────────────────────┐    │
        │  │  ┌─────────────────────────────────────────┐    │    │
        │  │  │  ┌─────────────────────────────────┐    │    │    │
        │  │  │  │         Your Message            │    │    │    │
        │  │  │  │        (encrypted)              │    │    │    │
        │  │  │  └─────────────────────────────────┘    │    │    │
        │  │  │      Recipient's Layer                  │    │    │
        │  │  └─────────────────────────────────────────┘    │    │
        │  │          Relay's Layer                          │    │
        │  └─────────────────────────────────────────────────┘    │
        │              Entry Node's Layer                         │
        └─────────────────────────────────────────────────────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────────────────────┐
        │  LAYER 3: Transport (UDP)                               │
        │                                                         │
        │  Raw encrypted bytes on the wire                        │
        │  No additional encryption at this layer                 │
        │  (encryption already applied above)                     │
        └─────────────────────────────────────────────────────────┘
```

### Onion Routing: How It Works

```
ONION ROUTING VISUALIZATION
============================

Alice wants to send to Bob through Relay R:

1. Alice builds the onion (inside-out):

   Start with message for Bob:
   ┌─────────────────────────────┐
   │  next_hop: 00000... (final) │
   │  message: "Hello!"          │
   └─────────────────────────────┘
                │
                ▼ Encrypt with Alice↔Bob shared secret
   ┌─────────────────────────────┐
   │  [Encrypted blob for Bob]   │
   └─────────────────────────────┘
                │
                ▼ Add relay layer
   ┌─────────────────────────────┐
   │  next_hop: Bob's ID         │
   │  payload: [blob for Bob]    │
   └─────────────────────────────┘
                │
                ▼ Encrypt with Alice↔Relay shared secret
   ┌─────────────────────────────┐
   │  [Encrypted blob for Relay] │
   └─────────────────────────────┘


2. Relay R receives and peels one layer:

   ┌─────────────────────────────┐
   │  [Encrypted blob for Relay] │
   └─────────────────────────────┘
                │
                ▼ Decrypt with Relay's key
   ┌─────────────────────────────┐
   │  next_hop: Bob's ID         │◄── Relay sees ONLY this
   │  payload: [blob for Bob]    │    (can't read inner content)
   └─────────────────────────────┘
                │
                ▼ Forward to Bob


3. Bob receives and peels final layer:

   ┌─────────────────────────────┐
   │  [Encrypted blob for Bob]   │
   └─────────────────────────────┘
                │
                ▼ Decrypt with Bob's key
   ┌─────────────────────────────┐
   │  next_hop: 00000... (final) │
   │  message: "Hello!"          │◄── Bob reads the message!
   └─────────────────────────────┘


WHAT EACH PARTY KNOWS:
======================

  Alice:  Knows she's sending to Bob (obviously)

  Relay:  Knows Alice sent something
          Knows to forward to Bob
          CANNOT read the message
          CANNOT prove Alice↔Bob are communicating
          (circuit ID could be for anyone)

  Bob:    Knows he received from Alice
          Can read the message

  Network Observer: Sees encrypted blobs
                    Cannot determine content
                    Cannot easily correlate sender/receiver
                    (timing jitter + cover traffic)
```

### Key Exchange

```
X25519 KEY EXCHANGE
===================

When Alice and Bob first connect:

    Alice                                              Bob
      │                                                  │
      │  Generate ephemeral keypair:                     │
      │  alice_priv, alice_pub = X25519_keygen()         │
      │                                                  │
      │                                                  │  Generate ephemeral keypair:
      │                                                  │  bob_priv, bob_pub = X25519_keygen()
      │                                                  │
      │──────── alice_pub (32 bytes) ──────────────────►│
      │                                                  │
      │◄─────── bob_pub (32 bytes) ────────────────────│
      │                                                  │
      │  shared_secret = X25519(alice_priv, bob_pub)     │  shared_secret = X25519(bob_priv, alice_pub)
      │                                                  │
      │           SAME 32-byte shared secret!            │
      │                                                  │
      │  Derive keys using HKDF:                         │  Derive keys using HKDF:
      │  - encryption_key                                │  - encryption_key
      │  - mac_key                                       │  - mac_key
      │                                                  │

Properties:
  - Forward secrecy: Ephemeral keys discarded after circuit
  - Key rotation: New keys every 30 seconds
  - No key transmission: Only public keys exchanged
```

---

## Why We're More Secure

### Comparison with Traditional Messengers

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TRADITIONAL MESSENGERS                                │
│                 (WhatsApp, Signal, Telegram)                            │
└─────────────────────────────────────────────────────────────────────────┘

    User A                    Server                     User B
       │                        │                          │
       │                   ┌────┴────┐                     │
       │                   │ Central │                     │
       │                   │ Server  │                     │
       │                   └────┬────┘                     │
       │                        │                          │
       │◄───── ALL TRAFFIC ─────┤───── ALL TRAFFIC ───────►│
       │                        │                          │

Server knows:
  ✗ Who you talk to
  ✗ When you talk
  ✗ How often
  ✗ Message sizes
  ✗ Your IP address
  ✗ Device info
  ✗ Phone number
  ✗ Contact list (often uploaded)

Even with E2E encryption:
  ✗ Metadata is NOT encrypted
  ✗ Server sees ALL metadata
  ✗ Subpoena = all your metadata


┌─────────────────────────────────────────────────────────────────────────┐
│                          CYXCHAT                                        │
│                    (Peer-to-Peer + Onion)                               │
└─────────────────────────────────────────────────────────────────────────┘

    User A ◄──────────────────────────────────────────────► User B
                              │
                              │ Direct P2P when possible
                              │
                    ┌─────────┴─────────┐
                    │  If NAT blocked:  │
                    │   Relay (can't    │
                    │   read content)   │
                    └───────────────────┘

No one knows:
  ✓ Message content (encrypted)
  ✓ Who talks to who (onion routing)
  ✓ Full communication patterns (cover traffic)
  ✓ Your real IP (NAT + relay obfuscation)

Relay (if used) knows:
  - Some node sent something to some node
  - That's it. No metadata. No content.
```

### Security Properties Compared

| Property | WhatsApp | Signal | CyxChat |
|----------|----------|--------|---------|
| End-to-End Encryption | Yes | Yes | Yes |
| Server sees metadata | **Yes** | **Yes** | **No** |
| Phone number required | **Yes** | **Yes** | **No** |
| Central server | **Yes** | **Yes** | **No** |
| Can be subpoenaed | **Yes** | **Yes** | **No** (nothing to give) |
| Forward secrecy | Yes | Yes | Yes |
| Onion routing | No | No | **Yes** |
| Cover traffic | No | No | **Yes** |
| Works offline/mesh | No | No | **Yes** (LoRa, BT, WiFi Direct) |
| Open source | Client only | Yes | **Yes** (full stack) |

### Specific Security Features

```
1. METADATA PROTECTION
======================

Traditional:
  Server log: "Alice → Bob, 10:42 PM, 847 bytes"

CyxChat:
  Relay log: "NodeX → NodeY, encrypted blob"
  (X and Y are circuit IDs, not real identities)


2. TIMING ANALYSIS RESISTANCE
=============================

Traditional:
  Send message → immediate network packet
  Easy to correlate sender ↔ receiver

CyxChat:
  ┌─────────────────────────────────────┐
  │  + Random delay (±30% jitter)       │
  │  + Cover traffic (dummy packets)    │
  │  + Circuit rotation (every 30s)     │
  │  = Hard to correlate timing         │
  └─────────────────────────────────────┘


3. REPLAY PROTECTION
====================

Each onion packet tracked:
  - 128 recent packet hashes stored
  - 90 second TTL
  - Duplicate → Dropped

Prevents:
  - Replay attacks
  - Traffic amplification


4. FORWARD SECRECY
==================

Even if an attacker captures your traffic AND
later gets your private key:

Traditional:
  ✗ Can decrypt old messages

CyxChat:
  ✓ Cannot decrypt old messages

Why? Ephemeral keys:
  - New circuit keys every 30 seconds
  - MPC MAC keys refreshed hourly
  - X25519 keypair rotated hourly
  - Old keys securely zeroed


5. SECURE MEMORY
================

All sensitive data:
  ┌────────────────────────────────────┐
  │  cyxwiz_secure_zero(buffer, len)   │
  │  - Overwrites with zeros           │
  │  - Prevents compiler optimization  │
  │  - Memory not left in RAM/swap     │
  └────────────────────────────────────┘

After use:
  - Keys zeroed
  - Plaintext zeroed
  - Shared secrets zeroed


6. NO SINGLE POINT OF FAILURE
=============================

Traditional:
  Server down = No messaging
  Server hacked = Everyone compromised
  Server subpoenaed = All data exposed

CyxChat:
  ┌─────────────────────────────────────────────────┐
  │  ✓ No central server to attack                  │
  │  ✓ No central database to breach                │
  │  ✓ Network routes around failures               │
  │  ✓ Works peer-to-peer, even without internet    │
  │  ✓ Nothing to subpoena                          │
  └─────────────────────────────────────────────────┘
```

### Attack Resistance Summary

```
┌────────────────────────────────────────────────────────────────────────┐
│                     ATTACK RESISTANCE MATRIX                           │
└────────────────────────────────────────────────────────────────────────┘

Attack Type              │ Traditional │ CyxChat │ How CyxChat Defends
─────────────────────────┼─────────────┼─────────┼─────────────────────────
Server breach            │     ✗       │    ✓    │ No server to breach
Metadata collection      │     ✗       │    ✓    │ Onion routing hides metadata
Traffic analysis         │     ✗       │    ✓    │ Cover traffic + timing jitter
Man-in-the-middle        │     ✓       │    ✓    │ X25519 key exchange
Replay attack            │     ?       │    ✓    │ Packet tracking + nonces
Subpoena/legal request   │     ✗       │    ✓    │ Nothing to give (no server)
Key compromise (future)  │     ✗       │    ✓    │ Forward secrecy
Endpoint compromise      │     ✗       │    ✗    │ (Both vulnerable if device is compromised)
Global passive adversary │     ✗       │    ~    │ Harder but not impossible
```

### Real-World Implications

```
SCENARIO: Government requests user data

Traditional Messenger:
  1. Government subpoenas company
  2. Company provides:
     - Your phone number
     - All contacts you messaged
     - Timestamps of all messages
     - IP addresses used
     - Device information
     - Group memberships
  3. Content may be encrypted, but metadata tells the story

CyxChat:
  1. Government subpoenas... who?
  2. No central server
  3. No company holding your data
  4. Bootstrap server only knows:
     - "Some node registered sometime"
     - No link to real identity
  5. Relay (if used) knows:
     - "Encrypted blobs passed through"
     - No content, no identities


SCENARIO: Server gets hacked

Traditional Messenger:
  - Attacker gets user database
  - Phone numbers, contacts, metadata
  - Potentially message history (if not E2E)
  - Can impersonate server to users

CyxChat:
  - There is no server to hack
  - Each user's data is ONLY on their device
  - Compromise one user ≠ compromise others
  - No central point of attack
```

---

## Summary

CyxChat provides security through:

1. **Decentralization**: No central server to attack, subpoena, or fail
2. **Onion Routing**: Multiple encryption layers hide who talks to whom
3. **Forward Secrecy**: Key rotation means past messages stay secret
4. **Metadata Protection**: Even relays can't see communication patterns
5. **Defense in Depth**: Multiple encryption layers at different levels

The core principle: **You own your data. No one else ever sees it.**

```
Traditional: "Trust us with your data"
CyxChat:     "We never see your data"
```

---

*Generated for educational purposes. CyxChat is open source at [repository URL].*
