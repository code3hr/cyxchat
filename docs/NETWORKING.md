# CyxChat Networking Guide

This document explains how CyxChat establishes secure, private peer-to-peer connections.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CyxChat Network Stack                     │
├─────────────────────────────────────────────────────────────────┤
│  Application Layer    │ Messages, Files, Presence               │
├───────────────────────┼─────────────────────────────────────────┤
│  Encryption Layer     │ Onion Routing (X25519 + XChaCha20)      │
├───────────────────────┼─────────────────────────────────────────┤
│  Connection Layer     │ Direct P2P or Relay Fallback            │
├───────────────────────┼─────────────────────────────────────────┤
│  Transport Layer      │ UDP with NAT Traversal                  │
├───────────────────────┼─────────────────────────────────────────┤
│  Discovery Layer      │ STUN + Bootstrap Server                 │
└───────────────────────┴─────────────────────────────────────────┘
```

---

## 1. STUN (Session Traversal Utilities for NAT)

### What it does
STUN discovers your **public IP address** when you're behind a router/NAT.

### The problem
```
Your PC knows:     192.168.1.50:12345   (private IP - not reachable from internet)
Internet sees:     203.0.113.99:54321   (public IP - what others can connect to)
```

Your device doesn't know its public address. STUN solves this.

### How it works
```
┌──────────┐                              ┌──────────────┐
│   You    │  ─── "What's my IP?" ───▶   │ STUN Server  │
│          │  ◀── "203.0.113.99:54321" ── │ (Google)     │
└──────────┘                              └──────────────┘
```

The STUN server simply echoes back the source address it sees.

### STUN servers used
```c
stun.l.google.com:19302
stun.cloudflare.com:19302
```

### What STUN discovers

| Result | Meaning |
|--------|---------|
| Public IP:Port | Your address others can reach |
| NAT Type: Open | No NAT, direct connection easy |
| NAT Type: Cone | Hole punch will work |
| NAT Type: Symmetric | Hole punch difficult, may need relay |
| NAT Type: Blocked | UDP blocked, relay required |

### When it runs
- Once at app startup
- Periodically to detect IP changes

---

## 2. UDP Hole Punching

### What it does
Creates a **direct peer-to-peer connection** through NAT firewalls.

### The problem
NAT blocks incoming connections by default:
```
Peer A behind NAT ──X──▶ Peer B behind NAT
                   (blocked!)
```

### How hole punching works

**Step 1: Both peers register with bootstrap server**
```
Peer A ──▶ Bootstrap: "I'm A, my public addr is 1.2.3.4:1111"
Peer B ──▶ Bootstrap: "I'm B, my public addr is 5.6.7.8:2222"
```

**Step 2: Exchange addresses**
```
Peer A ──▶ Bootstrap: "Where is B?"
Bootstrap ──▶ A: "B is at 5.6.7.8:2222"
Bootstrap ──▶ B: "A wants to connect, they're at 1.2.3.4:1111"
```

**Step 3: Simultaneous punch**
```
Peer A ────── PUNCH packet ──────▶ 5.6.7.8:2222
Peer B ────── PUNCH packet ──────▶ 1.2.3.4:1111
```

Both NATs see outgoing traffic and create a "hole" allowing replies.

**Step 4: Direct connection established**
```
Peer A ◀═══════ Direct P2P ═══════▶ Peer B
```

### Punch packet format
```c
struct {
    uint8_t  type;       // 0xF4 = PUNCH, 0xF5 = PUNCH_ACK
    uint8_t  sender_id[32];
    uint32_t punch_id;
}
```

### Timing
- 5 punch attempts
- 50ms between attempts
- ~500ms total before giving up

### Success rate by NAT type

| Your NAT | Peer's NAT | Success |
|----------|------------|---------|
| Cone | Cone | ~95% |
| Cone | Symmetric | ~50% |
| Symmetric | Symmetric | ~10% |
| Any | Blocked | 0% |

---

## 3. Relay (Fallback)

### What it does
Routes traffic through the bootstrap server when direct connection fails.

### When it's used
- Symmetric NAT on both sides
- Corporate firewalls blocking UDP
- Hole punch timeout after 5 attempts

### How it works
```
┌────────┐         ┌─────────────────┐         ┌────────┐
│ Peer A │ ──────▶ │ Bootstrap/Relay │ ──────▶ │ Peer B │
│        │ ◀────── │     Server      │ ◀────── │        │
└────────┘         └─────────────────┘         └────────┘
```

Every packet goes: A → Server → B

### Comparison: Direct vs Relay

| Aspect | Direct (Hole Punch) | Relay |
|--------|---------------------|-------|
| Path | A ↔ B | A ↔ Server ↔ B |
| Latency | ~30ms | ~100-200ms |
| Bandwidth | Unlimited | Server-limited |
| Privacy | No middleman | Server sees metadata |
| Reliability | May fail | Always works |

### Relay message format
```c
struct {
    uint8_t  type;           // 0xF2 = RELAY_DATA
    uint8_t  dest_id[32];    // Who to forward to
    uint8_t  payload[];      // Encrypted data
}
```

### Privacy note
Relay server sees:
- Source/destination node IDs
- Packet sizes and timing
- **NOT** message content (encrypted)

---

## 4. Onion Routing

### What it does
Provides **anonymous, end-to-end encrypted** messaging through multiple relay nodes.

### Why "onion"?
Like an onion, messages have layers of encryption that are "peeled" at each hop.

### How it works

**Sending a message through 3 hops:**
```
You → Hop1 → Hop2 → Hop3 → Destination

Message structure (layers):
┌─────────────────────────────────────────────────┐
│ Encrypt for Hop1:                               │
│  ┌───────────────────────────────────────────┐  │
│  │ Encrypt for Hop2:                         │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │ Encrypt for Hop3:                   │  │  │
│  │  │  ┌───────────────────────────────┐  │  │  │
│  │  │  │ Encrypt for Destination:      │  │  │  │
│  │  │  │  ┌─────────────────────────┐  │  │  │  │
│  │  │  │  │ Actual message content  │  │  │  │  │
│  │  │  │  └─────────────────────────┘  │  │  │  │
│  │  │  └───────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

**At each hop:**
```
Hop1: Decrypt outer layer → sees "forward to Hop2" → forwards
Hop2: Decrypt next layer → sees "forward to Hop3" → forwards
Hop3: Decrypt next layer → sees "forward to Dest" → forwards
Dest: Decrypt final layer → reads message
```

### What each node knows

| Node | Knows | Doesn't Know |
|------|-------|--------------|
| Hop1 | Sender, Hop2 | Destination, content |
| Hop2 | Hop1, Hop3 | Sender, destination, content |
| Hop3 | Hop2, Dest | Sender, content |
| Dest | Hop3, content | Sender (anonymous!) |

### Hop count settings
```
Standard (2 hops):  You → Relay → Destination
High (5 hops):      You → R1 → R2 → R3 → R4 → Destination
Maximum (8 hops):   You → R1 → R2 → R3 → R4 → R5 → R6 → R7 → Destination
```

More hops = more anonymity, but higher latency and smaller payload.

### Payload size by hops
Each hop adds 104 bytes overhead (32B ephemeral key + 40B encryption + 32B next_hop).

| Hops | Max Payload |
|------|-------------|
| 2 | ~1.2 KB |
| 5 | ~873 B |
| 8 | ~561 B |

---

## 5. Encryption

### Algorithms used

| Purpose | Algorithm | Key Size |
|---------|-----------|----------|
| Key Exchange | X25519 (Curve25519 ECDH) | 256-bit |
| Symmetric Encryption | XChaCha20-Poly1305 | 256-bit |
| Hashing | BLAKE2b | 256-bit |
| Random | libsodium CSPRNG | - |

### Key exchange (X25519)
Each node has an X25519 keypair:
```
Private key: 32 bytes (secret)
Public key:  32 bytes (shared with peers)
```

When two peers connect:
```
A's private + B's public → Shared secret (32 bytes)
B's private + A's public → Same shared secret
```

This shared secret encrypts all communication.

### Message encryption (XChaCha20-Poly1305)
```
┌─────────────────────────────────────────────┐
│ Nonce (24 bytes) │ Ciphertext │ Tag (16 bytes) │
└─────────────────────────────────────────────┘
```

- **XChaCha20**: Stream cipher (fast, secure)
- **Poly1305**: Authentication tag (detects tampering)
- **Nonce**: Random, never reused (prevents replay attacks)

### Per-hop encryption (Onion)
Each onion layer uses:
```
Ephemeral X25519 keypair (generated per message)
    ↓
ECDH with hop's public key → Per-hop shared secret
    ↓
XChaCha20-Poly1305 encrypt with that secret
```

### Key refresh
Keys are refreshed periodically for forward secrecy:
- X25519 keypairs: Every hour
- Session keys: Every message (ephemeral)

---

## 6. Complete Message Flow

### Sending "Hello" to a peer:

```
1. APP LAYER
   Message: "Hello"

2. ONION LAYER
   Build circuit: You → Hop1 → Hop2 → Peer
   Encrypt layers: [[[["Hello"]Peer]Hop2]Hop1]

3. CONNECTION LAYER
   Check: Direct connection to Hop1?
   Yes → Send directly
   No  → Send via relay

4. TRANSPORT LAYER
   UDP packet to Hop1's IP:port

5. NETWORK
   Packet travels through internet

6. HOP1 RECEIVES
   Decrypt outer layer → Forward to Hop2

7. HOP2 RECEIVES
   Decrypt layer → Forward to Peer

8. PEER RECEIVES
   Decrypt final layer → Read "Hello"
```

### Connection establishment flow:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. STARTUP                                                  │
│    STUN query → Discover public IP: 1.2.3.4:5678           │
│    NAT type: Cone (hole punch OK)                          │
├─────────────────────────────────────────────────────────────┤
│ 2. REGISTRATION                                             │
│    Connect to bootstrap server                              │
│    Register: "I'm NodeID xyz, at 1.2.3.4:5678"             │
├─────────────────────────────────────────────────────────────┤
│ 3. PEER DISCOVERY                                           │
│    Request peer's address from bootstrap                    │
│    Receive: "Peer is at 5.6.7.8:9999"                      │
├─────────────────────────────────────────────────────────────┤
│ 4. HOLE PUNCH (try direct)                                  │
│    Send 5 PUNCH packets to 5.6.7.8:9999                    │
│    Wait for PUNCH_ACK...                                    │
│    ├─ Success → Direct P2P established!                     │
│    └─ Timeout → Fall back to relay                         │
├─────────────────────────────────────────────────────────────┤
│ 5. KEY EXCHANGE                                             │
│    Exchange X25519 public keys                              │
│    Compute shared secret                                    │
├─────────────────────────────────────────────────────────────┤
│ 6. READY                                                    │
│    Encrypted, private messaging available                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Security Properties

| Property | How it's achieved |
|----------|-------------------|
| **Confidentiality** | XChaCha20-Poly1305 encryption |
| **Integrity** | Poly1305 authentication tag |
| **Anonymity** | Onion routing (sender hidden) |
| **Forward Secrecy** | Ephemeral keys, hourly refresh |
| **No Central Trust** | E2E encryption, server can't read |
| **NAT Traversal** | STUN + UDP hole punching |
| **Reliability** | Relay fallback when direct fails |

---

## 8. Glossary

| Term | Definition |
|------|------------|
| **NAT** | Network Address Translation - router maps private IPs to public |
| **STUN** | Protocol to discover public IP address |
| **Hole Punch** | Technique to establish direct P2P through NAT |
| **Relay** | Server that forwards packets between peers |
| **Onion Routing** | Layered encryption through multiple hops |
| **X25519** | Elliptic curve for key exchange |
| **XChaCha20** | Stream cipher for encryption |
| **Poly1305** | MAC for message authentication |
| **Bootstrap** | Server for initial peer discovery |
| **Forward Secrecy** | Past messages stay secure if keys leak |
