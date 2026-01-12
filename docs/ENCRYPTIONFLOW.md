# CyxChat Encryption Flow

This document describes how encryption works between two nodes in a P2P communication scenario.

## Overview

CyxChat uses a multi-layered encryption approach:

1. **X25519 Key Exchange** - Establishes shared secrets between peers
2. **XChaCha20-Poly1305** - Symmetric encryption for message content
3. **Onion Routing** - Layered encryption for anonymous routing (optional)

## Key Exchange Flow

### Step 1: Keypair Generation

When a node starts, it generates an X25519 keypair:

```
Node A:                          Node B:
┌─────────────────┐              ┌─────────────────┐
│ Generate        │              │ Generate        │
│ X25519 keypair  │              │ X25519 keypair  │
│                 │              │                 │
│ sk_a (32 bytes) │              │ sk_b (32 bytes) │
│ pk_a (32 bytes) │              │ pk_b (32 bytes) │
└─────────────────┘              └─────────────────┘
```

### Step 2: Public Key Exchange via Discovery

Nodes exchange public keys through the discovery protocol:

```
Node A                Bootstrap Server              Node B
  │                         │                          │
  │─── REGISTER ───────────>│                          │
  │    (node_id_a)          │                          │
  │                         │                          │
  │                         │<─── REGISTER ────────────│
  │                         │     (node_id_b)          │
  │                         │                          │
  │<── PEER_LIST ──────────│────> PEER_LIST ──────────>│
  │    (node_id_b, addr)    │     (node_id_a, addr)    │
  │                         │                          │
  │                                                    │
  │──────────── ANNOUNCE (pk_a) ──────────────────────>│
  │                                                    │
  │<─────────── ANNOUNCE_ACK (pk_b) ───────────────────│
  │                                                    │
```

The ANNOUNCE message contains the sender's X25519 public key:

```c
typedef struct {
    uint8_t type;           // CYXWIZ_DISC_ANNOUNCE
    uint8_t version;        // Protocol version (1)
    cyxwiz_node_id_t node_id;   // 32 bytes
    uint8_t capabilities;
    uint16_t port;
    uint8_t pubkey[32];     // X25519 public key
} cyxwiz_disc_announce_t;   // 69 bytes total
```

### Step 3: Shared Secret Computation

Both nodes compute the same shared secret using X25519 ECDH:

```
Node A                                    Node B
┌────────────────────┐                    ┌────────────────────┐
│                    │                    │                    │
│ shared = X25519(   │                    │ shared = X25519(   │
│   sk_a,            │   ═══════════════  │   sk_b,            │
│   pk_b             │   Same 32-byte     │   pk_a             │
│ )                  │   shared secret    │ )                  │
│                    │                    │                    │
└────────────────────┘                    └────────────────────┘
```

The shared secret is computed using `crypto_scalarmult()` from libsodium:

```c
cyxwiz_error_t cyxwiz_onion_add_peer_key(
    cyxwiz_onion_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    const uint8_t *peer_pubkey
) {
    // Compute shared secret: shared = sk_ours * pk_peer
    crypto_scalarmult(shared_secret, ctx->secret_key, peer_pubkey);

    // Store for future message encryption
    store_peer_key(ctx, peer_id, shared_secret, peer_pubkey);
}
```

## Message Encryption Flow

### Direct Message (1-hop)

For direct P2P communication without onion routing:

```
Node A (Sender)                           Node B (Receiver)
┌─────────────────────────────────────┐   ┌─────────────────────────────────────┐
│ 1. Lookup shared_secret for Node B  │   │                                     │
│                                     │   │                                     │
│ 2. Generate random nonce (24 bytes) │   │                                     │
│                                     │   │                                     │
│ 3. Encrypt with XChaCha20-Poly1305: │   │ 4. Receive packet                   │
│    ciphertext = encrypt(            │──>│                                     │
│      plaintext,                     │   │ 5. Extract nonce from packet        │
│      shared_secret,                 │   │                                     │
│      nonce                          │   │ 6. Decrypt with XChaCha20-Poly1305: │
│    )                                │   │    plaintext = decrypt(             │
│                                     │   │      ciphertext,                    │
│                                     │   │      shared_secret,                 │
│                                     │   │      nonce                          │
│                                     │   │    )                                │
└─────────────────────────────────────┘   └─────────────────────────────────────┘
```

**Packet Format:**
```
┌──────────┬───────────┬──────────────────────────────────┐
│ Type (1) │ Nonce(24) │ Ciphertext + Auth Tag (16)       │
└──────────┴───────────┴──────────────────────────────────┘
```

### Onion-Routed Message (Multi-hop)

For anonymous routing through intermediate nodes:

```
Node A ──────> Hop 1 ──────> Hop 2 ──────> Node B
(Sender)      (Relay)       (Relay)       (Receiver)

Encryption layers (wrapped inside-out):

Layer 3 (innermost): encrypt(payload, key_B)
Layer 2:             encrypt(Layer3 || next_hop_B, key_Hop2)
Layer 1 (outermost): encrypt(Layer2 || next_hop_Hop2, key_Hop1)
```

Each hop peels one layer:

```
┌───────────────────────────────────────────────────────────────────────┐
│ Hop 1 receives:                                                       │
│   [Encrypted Layer 1]                                                 │
│                                                                       │
│ Hop 1 decrypts:                                                       │
│   inner = decrypt(packet, key_Hop1)                                   │
│   next_hop = inner.next_hop  // Points to Hop 2                       │
│   forward inner.data to next_hop                                      │
└───────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌───────────────────────────────────────────────────────────────────────┐
│ Hop 2 receives:                                                       │
│   [Encrypted Layer 2]                                                 │
│                                                                       │
│ Hop 2 decrypts:                                                       │
│   inner = decrypt(packet, key_Hop2)                                   │
│   next_hop = inner.next_hop  // Points to Node B                      │
│   forward inner.data to next_hop                                      │
└───────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌───────────────────────────────────────────────────────────────────────┐
│ Node B receives:                                                      │
│   [Encrypted Layer 3]                                                 │
│                                                                       │
│ Node B decrypts:                                                      │
│   plaintext = decrypt(packet, key_B)                                  │
│   // next_hop is all zeros = final destination                        │
│   deliver plaintext to application                                    │
└───────────────────────────────────────────────────────────────────────┘
```

## Key Derivation

Per-hop keys are derived from the shared secret to prevent key reuse:

```c
cyxwiz_error_t cyxwiz_onion_derive_hop_key(
    const uint8_t *shared_secret,
    const cyxwiz_node_id_t *sender,
    const cyxwiz_node_id_t *receiver,
    uint8_t *key_out
) {
    // Domain separation: "cyxwiz-hop-key"
    uint8_t context[32 + 32 + 14];
    memcpy(context, sender->id, 32);
    memcpy(context + 32, receiver->id, 32);
    memcpy(context + 64, "cyxwiz-hop-key", 14);

    // BLAKE2b-256 key derivation
    crypto_generichash(key_out, 32, context, sizeof(context),
                       shared_secret, 32);
}
```

## Ephemeral Keys (Forward Secrecy)

For enhanced forward secrecy, each onion layer uses an ephemeral key:

```
Sender generates:
  - ephemeral_sk_1, ephemeral_pk_1 for Hop 1
  - ephemeral_sk_2, ephemeral_pk_2 for Hop 2
  - ephemeral_sk_3, ephemeral_pk_3 for Node B

Each layer includes the ephemeral public key:
  [ephemeral_pk | encrypted_data]

Receiver computes:
  layer_key = X25519(receiver_sk, ephemeral_pk)
```

This ensures that even if long-term keys are compromised, past messages cannot be decrypted.

## Cryptographic Primitives

| Operation | Algorithm | Key Size | Nonce Size | Auth Tag |
|-----------|-----------|----------|------------|----------|
| Key Exchange | X25519 | 32 bytes | N/A | N/A |
| Encryption | XChaCha20-Poly1305 | 32 bytes | 24 bytes | 16 bytes |
| Hashing | BLAKE2b | 32 bytes | N/A | N/A |

## Security Properties

1. **Confidentiality**: XChaCha20-Poly1305 AEAD ensures data is encrypted
2. **Integrity**: Poly1305 MAC detects any tampering
3. **Forward Secrecy**: Ephemeral keys per message (optional)
4. **Anonymity**: Onion routing hides sender identity
5. **Replay Protection**: Nonces and packet hashes prevent replay attacks

## Code Flow

```c
// 1. Node startup - creates onion context with X25519 keypair
cyxwiz_onion_create(&onion, router, &local_id);

// 2. Get our public key for announcements
uint8_t pubkey[32];
cyxwiz_onion_get_pubkey(onion, pubkey);

// 3. Discovery announces our public key
cyxwiz_discovery_set_pubkey(discovery, pubkey);
cyxwiz_discovery_set_key_callback(discovery, on_peer_key, onion);

// 4. When peer key received via announcement
void on_peer_key(const cyxwiz_node_id_t *peer_id,
                 const uint8_t *peer_pubkey, void *ctx) {
    cyxwiz_onion_add_peer_key(ctx, peer_id, peer_pubkey);
}

// 5. Send encrypted message to peer
cyxwiz_onion_send_to(onion, &peer_id, data, len);
```

## Packet Size Constraints

Due to the 250-byte packet limit:

| Hop Count | Max Payload |
|-----------|-------------|
| 1 hop | 139 bytes |
| 2 hops | 35 bytes |
| 3 hops | Not supported with ephemeral keys |

## Error Handling

- `CYXWIZ_ERR_NO_KEY`: No shared key with destination (key exchange not completed)
- `CYXWIZ_ERR_CRYPTO`: Decryption failed (tampering or wrong key)
- `CYXWIZ_ERR_PACKET_TOO_LARGE`: Payload exceeds max for hop count

---

## CyxChat Server (cyxchat-server)

### Purpose

The `cyxchat-server` is a combined **Bootstrap + Relay Server** that facilitates P2P communication. It is NOT involved in encryption - all messages are end-to-end encrypted before reaching the server.

### Server Roles

#### 1. Bootstrap Server (Peer Discovery)

The bootstrap server helps nodes find each other:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            BOOTSTRAP FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Node A                    CyxChat Server                    Node B         │
│    │                            │                              │            │
│    │── REGISTER (0xF0) ────────>│                              │            │
│    │   {node_id_a, port}        │                              │            │
│    │                            │                              │            │
│    │<── REGISTER_ACK (0xF1) ────│                              │            │
│    │                            │                              │            │
│    │                            │<── REGISTER (0xF0) ──────────│            │
│    │                            │    {node_id_b, port}         │            │
│    │                            │                              │            │
│    │                            │──> REGISTER_ACK (0xF1) ──────│            │
│    │                            │                              │            │
│    │<── PEER_LIST (0xF2) ───────│────> PEER_LIST (0xF2) ───────│            │
│    │    [node_id_b, ip:port]    │      [node_id_a, ip:port]    │            │
│    │                            │                              │            │
│    │                                                           │            │
│    │══════════════ Direct P2P Connection ══════════════════════│            │
│    │              (server no longer involved)                  │            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Server tracks registered peers (node ID → public IP:port mapping)
- Periodically sends peer lists so nodes can discover each other
- Once peers know each other's addresses, they communicate directly
- Server sees node IDs and IP addresses, but NOT message content

#### 2. Relay Server (NAT Traversal Fallback)

When direct P2P connection fails (symmetric NAT, firewalls), the server relays encrypted data:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              RELAY FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Node A                    CyxChat Server                    Node B         │
│    │                            │                              │            │
│    │                            │                              │            │
│    │   ╔═══════════════════════════════════════════════════╗  │            │
│    │   ║  Direct connection failed (NAT/firewall)          ║  │            │
│    │   ╚═══════════════════════════════════════════════════╝  │            │
│    │                            │                              │            │
│    │── RELAY_CONNECT (0xE0) ───>│                              │            │
│    │   {from: A, to: B}         │                              │            │
│    │                            │                              │            │
│    │<── RELAY_CONNECT_ACK(0xE1)─│                              │            │
│    │                            │                              │            │
│    │── RELAY_DATA (0xE3) ──────>│──> RELAY_DATA (0xE3) ───────>│            │
│    │   {from: A, to: B,         │    {from: A, to: B,          │            │
│    │    data: [ENCRYPTED]}      │     data: [ENCRYPTED]}       │            │
│    │                            │                              │            │
│    │<── RELAY_DATA (0xE3) ──────│<── RELAY_DATA (0xE3) ────────│            │
│    │   {from: B, to: A,         │    {from: B, to: A,          │            │
│    │    data: [ENCRYPTED]}      │     data: [ENCRYPTED]}       │            │
│    │                            │                              │            │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Relay is only used when direct hole punching fails
- Server forwards encrypted packets - it CANNOT read content
- Server only sees: source node ID, destination node ID, packet size
- All data is encrypted with X25519/XChaCha20-Poly1305 before relay

### Protocol Messages

| Type | Name | Direction | Purpose |
|------|------|-----------|---------|
| `0xF0` | REGISTER | Client → Server | Register node with server |
| `0xF1` | REGISTER_ACK | Server → Client | Acknowledge registration |
| `0xF2` | PEER_LIST | Server → Client | List of known peers |
| `0xF3` | CONNECT_REQ | Client → Server | Request connection to peer |
| `0xE0` | RELAY_CONNECT | Client → Server | Request relay to peer |
| `0xE1` | RELAY_CONNECT_ACK | Server → Client | Relay established |
| `0xE3` | RELAY_DATA | Bidirectional | Relayed encrypted data |
| `0xE4` | RELAY_KEEPALIVE | Bidirectional | Keep relay session alive |

### Running the Server

```bash
# Default port 7777
./cyxchat-server

# Custom port
./cyxchat-server 8888

# Output:
# CyxChat Server (Bootstrap + Relay)
# ===================================
# Listening on UDP port 7777
# Press Ctrl+C to stop
#
# Environment variables for clients:
#   CYXWIZ_BOOTSTRAP=<this_server_ip>:7777
#   CYXCHAT_RELAY=<this_server_ip>:7777
```

### Client Configuration

Set the bootstrap server address when connecting:

```dart
// Flutter/Dart client
final chatProvider = ChatProvider();
await chatProvider.connect(
  bootstrapServer: '192.168.1.100:7777',  // Server IP:port
);
```

```c
// C library
cyxchat_conn_create(&ctx, "192.168.1.100:7777", &local_id);
```

### Security Model

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    WHAT THE SERVER CAN SEE                               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ✓ Node IDs (32-byte public identifiers)                                │
│  ✓ Public IP addresses and ports                                        │
│  ✓ When nodes are online (registration timestamps)                      │
│  ✓ Who is communicating with whom (node ID pairs)                       │
│  ✓ Message sizes and timing                                             │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│                    WHAT THE SERVER CANNOT SEE                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ✗ Message content (encrypted with X25519 shared secret)                │
│  ✗ Usernames or display names (local only)                              │
│  ✗ Contact lists (stored locally)                                        │
│  ✗ Chat history (stored locally)                                         │
│  ✗ Private keys (never leave the device)                                │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### End-to-End Encryption with Server

Even when using the relay server, messages remain encrypted:

```
Node A                        Server                         Node B
┌────────────────┐                                     ┌────────────────┐
│                │                                     │                │
│ plaintext:     │                                     │                │
│ "Hello Bob!"   │                                     │                │
│       │        │                                     │                │
│       ▼        │                                     │                │
│ ┌────────────┐ │                                     │                │
│ │ Encrypt    │ │                                     │                │
│ │ with       │ │                                     │                │
│ │ shared_key │ │                                     │                │
│ └────────────┘ │                                     │                │
│       │        │                                     │                │
│       ▼        │                                     │                │
│ ciphertext:    │         Server only sees:          │                │
│ 0x8f3a...b2c1  │────────>  0x8f3a...b2c1  ─────────>│ ciphertext:    │
│                │         (opaque bytes)             │ 0x8f3a...b2c1  │
│                │                                     │       │        │
│                │                                     │       ▼        │
│                │                                     │ ┌────────────┐ │
│                │                                     │ │ Decrypt    │ │
│                │                                     │ │ with       │ │
│                │                                     │ │ shared_key │ │
│                │                                     │ └────────────┘ │
│                │                                     │       │        │
│                │                                     │       ▼        │
│                │                                     │ plaintext:     │
│                │                                     │ "Hello Bob!"   │
└────────────────┘                                     └────────────────┘
```

### Peer Timeout and Cleanup

- Peers must re-register every 60 seconds (default)
- Server removes peers after 120 seconds of inactivity
- Relay connections timeout after 120 seconds without keepalive
- Maximum 256 concurrent registered peers (configurable)
