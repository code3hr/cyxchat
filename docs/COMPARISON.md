# CyxChat vs Other Secure Messengers

A technical comparison of CyxChat with Meshtastic, Signal, Briar, and Matrix/Session.

---

## Quick Comparison Table

| Feature | CyxChat | Signal | Briar | Session | Matrix | Meshtastic |
|---------|---------|--------|-------|---------|--------|------------|
| **Requires Phone Number** | No | Yes | No | No | No | No |
| **Requires Email** | No | No | No | No | Optional | No |
| **Central Servers** | No | Yes | No | Decentralized | Federated | No |
| **Works Offline/Mesh** | No | No | Yes (WiFi/BT) | No | No | Yes |
| **Metadata Protection** | Onion routing | Limited | Tor | Onion routing | No | Limited |
| **NAT Traversal** | STUN + Relay | Server-based | Tor | Onion network | Server-based | N/A (radio) |
| **End-to-End Encryption** | Yes | Yes | Yes | Yes | Yes | Limited |
| **Open Source** | Yes | Yes | Yes | Yes | Yes | Yes |
| **Identity** | Public key | Phone # | Public key | Session ID | Matrix ID | Device ID |
| **Username System** | Yes (DNS) | No | No | No | Yes | No |
| **Read Receipts** | Yes | Yes | No | No | Yes | No |
| **Message Replies** | Yes | Yes | No | Yes | Yes | No |
| **Group Chat** | Yes (50 max) | Yes | Yes | Yes | Yes | Yes |
| **Voice/Video** | Planned (WebRTC) | Yes (WebRTC) | No | No | Yes | No |
| **File Transfer** | Yes (64KB) | Yes | Yes | Yes | Yes | No |

---

## Detailed Comparison

### Signal

**What it is:** The gold standard for encrypted messaging. Uses phone numbers for identity.

**Pros:**
- Excellent encryption (Signal Protocol)
- Large user base
- Easy to use
- Voice/video calls

**Cons:**
- Requires phone number (links to real identity)
- Centralized servers (Signal Foundation controls infrastructure)
- Servers see metadata (who talks to whom, when)
- Single point of failure
- Can be blocked by governments

**CyxChat difference:**
- No phone number required - truly anonymous identity
- No central servers - peer-to-peer mesh
- Onion routing hides metadata
- Cannot be "shut down" - no single point of failure

---

### Briar

**What it is:** Peer-to-peer messenger designed for activists. Uses Tor for internet, direct WiFi/Bluetooth for local mesh.

**Pros:**
- No central servers
- Works over Tor (anonymity)
- Direct device-to-device over WiFi/Bluetooth
- Designed for hostile environments

**Cons:**
- Tor is slow (high latency)
- WiFi Direct/Bluetooth range is limited (~100m)
- No relay fallback for NAT traversal
- Android only (no iOS, limited desktop)
- Battery intensive

**CyxChat difference:**
- UDP hole punching for NAT traversal (works behind most routers)
- Relay fallback when direct connection fails
- Cross-platform (Windows, macOS, Linux, iOS, Android)
- Lower latency than Tor

---

### Session

**What it is:** Fork of Signal without phone numbers. Uses a decentralized network of "Service Nodes."

**Pros:**
- No phone number required
- Onion routing (like CyxChat)
- Decentralized storage nodes
- Good UX

**Cons:**
- Service Nodes require staking (Oxen cryptocurrency)
- Network depends on crypto incentives
- Still somewhat centralized (foundation controls protocol)
- Messages stored on nodes (encrypted, but still stored)

**CyxChat difference:**
- No cryptocurrency or staking required
- True peer-to-peer (no storage nodes)
- Messages only exist on sender/recipient devices
- No foundation or company controlling the network
- Simpler architecture

---

### Matrix / Element

**What it is:** Federated protocol for real-time communication. Element is the main client.

**Pros:**
- Federated (anyone can run a server)
- Feature-rich (rooms, threads, reactions)
- Bridges to other platforms
- Good for organizations

**Cons:**
- Servers see metadata
- Complex protocol (many implementations have bugs)
- Federation means trusting server operators
- Not designed for anonymity
- Heavy resource usage

**CyxChat difference:**
- No servers to trust or operate
- Simpler protocol (smaller attack surface)
- Designed for privacy, not features
- Lightweight

---

### Meshtastic

**What it is:** LoRa mesh networking for text messaging. Works without internet.

**Pros:**
- Works completely offline
- Long range (several kilometers with LoRa)
- Great for emergencies/disasters
- Low power consumption

**Cons:**
- Very limited bandwidth (short messages only)
- Encryption is basic (AES-128, shared keys)
- No forward secrecy
- Metadata visible to mesh participants
- Requires special hardware (LoRa radio)

**CyxChat difference:**
- Built on CyxWiz protocol with efficient packet design
- Onion routing with 3-hop maximum
- Forward secrecy with rotating keys
- UDP with NAT traversal for reliable connectivity

---

## CyxChat Unique Features

### 1. Decentralized Username System (DNS)

Unlike other messengers where you share a long public key or Session ID, CyxChat has a **gossip-based DNS** for human-readable usernames:

```
Instead of sharing: 9db1b1b1b1b1b1b1a2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5
You share: @alice
```

**How it works:**
- Register username locally (no central registry)
- Username propagates through peer gossip
- Lookups query connected peers
- No single point of failure

**Trade-off:** Username uniqueness is "first seen wins" within your peer network. In practice, collisions are rare.

### 2. Message Delivery Status

Full message lifecycle tracking:
- ⏳ **Pending** - Queued locally
- ✓ **Sent** - Delivered to network
- ✓✓ **Delivered** - Recipient received
- 👁 **Read** - Recipient opened message

### 3. Long Message Fragmentation

Messages up to **4096 characters** are automatically:
- Split into 80-byte fragments
- Sent via onion routing (anonymous)
- Reassembled on recipient's device
- Delivered as single message

### 4. UDP Transport with NAT Traversal

CyxChat uses UDP for reliable peer-to-peer connectivity:
- **STUN** - Discover public IP address
- **UDP Hole Punching** - Direct P2P when possible
- **Relay Fallback** - Via bootstrap server when direct fails

---

## Security Deep Dive

### What Makes CyxChat Secure?

#### 1. No Identity Linkage
- Your identity is a 64-character public key
- Not linked to phone, email, or any real-world identifier
- New identity = new keypair (trivial to create)

#### 2. End-to-End Encryption
```
Algorithm: XChaCha20-Poly1305
Key Exchange: X25519 (Curve25519 ECDH)
Key Size: 256-bit
```
- Same cryptographic primitives as Signal, WireGuard
- Libsodium implementation (audited, widely used)

#### 3. Onion Routing (Metadata Protection)
```
You → Hop 1 → Hop 2 → Hop 3 → Recipient

Each hop only knows:
- Previous hop
- Next hop
- NOT the origin or destination
```
- 3-hop circuits by default
- Per-hop encryption with ephemeral keys
- Circuit rotation for forward secrecy

#### 4. No Central Point of Failure
```
Traditional:    You → Server → Recipient
                     ↑
              (Server sees everything)

CyxChat:        You → Peer → Peer → Recipient
                     ↑       ↑
              (Each peer sees only adjacent hops)
```

#### 5. Minimal Attack Surface
- No accounts to hack
- No servers to compromise
- No databases to breach
- Code is simple and auditable

---

## Honest Limitations

### What CyxChat Does NOT Do (Yet)

| Feature | Status | Why |
|---------|--------|-----|
| Voice/Video Calls | Planned | Requires reliable low-latency paths |
| Large File Transfer | Planned | Current limit ~64KB inline, chunked for larger |
| Offline Messages | Limited | Requires recipient online (no store-and-forward) |
| Group Scalability | Limited | Max 50 members per group |
| Key Verification | Basic | No QR code verification yet |

### Known Trade-offs

1. **Latency vs Privacy**: Onion routing adds latency (~100-500ms per hop)
2. **Bandwidth vs Anonymity**: Onion overhead reduces effective payload
3. **Availability vs Decentralization**: Need bootstrap server for initial discovery
4. **Simplicity vs Features**: Fewer features than Signal/Matrix

---

## Why Choose CyxChat?

### Choose CyxChat If You Need:

1. **True Anonymity**
   - No phone number, no email, no identity
   - Metadata hidden via onion routing

2. **Censorship Resistance**
   - No central server to block
   - UDP with NAT traversal works behind most networks

3. **Self-Sovereignty**
   - You control your identity (it's just a keypair)
   - No company can ban you or read your messages

4. **Direct P2P Communication**
   - UDP hole punching for direct connections
   - Relay fallback ensures connectivity

5. **Simplicity**
   - Clean, auditable codebase
   - No blockchain, no tokens, no complexity

### Choose Signal If You Need:
- Voice/video calls today
- Large user base (easier to onboard contacts)
- Proven track record

### Choose Briar If You Need:
- Activist-grade security in hostile environments
- Tor integration
- Android-only is acceptable

### Choose Matrix If You Need:
- Organization/team features
- Bridges to other platforms
- Self-hosted server option

---

## Technical Architecture Comparison

### Signal
```
┌──────────┐     ┌──────────────┐     ┌──────────┐
│  Sender  │────▶│Signal Servers│────▶│ Receiver │
└──────────┘     └──────────────┘     └──────────┘
                       │
              Metadata visible here
```

### Briar (over Tor)
```
┌──────────┐     ┌─────┐     ┌─────┐     ┌─────┐     ┌──────────┐
│  Sender  │────▶│Tor 1│────▶│Tor 2│────▶│Tor 3│────▶│ Receiver │
└──────────┘     └─────┘     └─────┘     └─────┘     └──────────┘
                 Onion routing via Tor network
```

### CyxChat
```
┌──────────┐     ┌──────┐     ┌──────┐     ┌──────┐     ┌──────────┐
│  Sender  │────▶│Peer 1│────▶│Peer 2│────▶│Peer 3│────▶│ Receiver │
└──────────┘     └──────┘     └──────┘     └──────┘     └──────────┘
                 Onion routing via CyxWiz mesh

                 OR (direct when possible):

┌──────────┐                              ┌──────────┐
│  Sender  │─────────UDP Hole Punch──────▶│ Receiver │
└──────────┘                              └──────────┘
```

---

## Protocol Comparison: CyxChat vs WebRTC

### Understanding the Protocols

**WebRTC** is the industry standard for real-time communication (audio/video). It's a full stack:

```
WebRTC Protocol Stack:

┌─────────────────────────────────────┐
│  Application (Video/Audio/Data)     │
├─────────────────────────────────────┤
│  SRTP (Secure Real-time Protocol)   │  ← Media encryption
│  SCTP (Stream Control)              │  ← Data channels
├─────────────────────────────────────┤
│  DTLS (Datagram TLS)                │  ← Key exchange
├─────────────────────────────────────┤
│  ICE (Interactive Connectivity)     │  ← NAT traversal
│    ├── STUN (discovery)             │
│    └── TURN (relay fallback)        │
├─────────────────────────────────────┤
│  UDP (preferred) / TCP (fallback)   │  ← Transport
└─────────────────────────────────────┘
```

**CyxChat Protocol** is a custom lightweight protocol optimized for text messaging:

```
CyxChat Protocol Stack:

┌─────────────────────────────────────┐
│  Application (Text/Files/Presence)  │
├─────────────────────────────────────┤
│  Onion Routing (optional)           │  ← Metadata protection
├─────────────────────────────────────┤
│  XChaCha20-Poly1305                 │  ← E2E encryption
├─────────────────────────────────────┤
│  X25519 Key Exchange                │  ← ECDH key agreement
├─────────────────────────────────────┤
│  STUN + UDP Hole Punch              │  ← NAT traversal
│    └── Relay fallback               │
├─────────────────────────────────────┤
│  UDP                                │  ← Transport
└─────────────────────────────────────┘
```

### Protocol Comparison Table

| Feature | CyxChat Protocol | WebRTC |
|---------|------------------|--------|
| **Primary Use** | Text, files, presence | Audio, video, data |
| **Transport** | UDP only | UDP preferred, TCP fallback |
| **NAT Traversal** | STUN + custom hole punch | ICE (STUN + TURN) |
| **Relay** | Custom relay server | TURN servers |
| **Encryption** | XChaCha20-Poly1305 | DTLS + SRTP |
| **Key Exchange** | X25519 ECDH | DTLS handshake |
| **Metadata Protection** | Onion routing (optional) | None |
| **Complexity** | Low (~5K lines) | High (~100K+ lines) |
| **Browser Support** | No (native only) | Yes (built into browsers) |
| **Codecs** | N/A | Opus, VP8, VP9, H.264, AV1 |
| **Bandwidth Adaptation** | N/A | Built-in |

### NAT Traversal Comparison

Both protocols solve the same problem but differently:

```
CyxChat NAT Traversal:

1. STUN discovery (get public IP:port)
2. Exchange addresses via bootstrap server
3. UDP hole punch (5 rapid packets)
4. Success → Direct P2P
5. Fail → Use relay server

WebRTC NAT Traversal (ICE):

1. Gather candidates (host, srflx, relay)
2. Exchange candidates via signaling
3. Connectivity checks (STUN binding)
4. Prioritize: direct > server reflexive > relay
5. Select best working path
```

| Aspect | CyxChat | WebRTC ICE |
|--------|---------|------------|
| Candidate types | 2 (direct, relay) | 3 (host, srflx, relay) |
| Fallback | Single relay | Multiple TURN servers |
| Trickle candidates | No | Yes |
| Candidate pairing | Simple | Full mesh testing |
| Connection time | Fast (~2s) | Varies (~1-5s) |

---

## How Major Apps Handle Text vs Calls

Every major messaging app uses **different protocols** for text and calls:

### Signal

```
┌─────────────────────────────────────────────┐
│                  Signal                      │
├─────────────────────┬───────────────────────┤
│    Text Messages    │    Voice/Video Calls  │
│    ──────────────   │    ────────────────   │
│    Signal Protocol  │    WebRTC             │
│    (custom)         │    (standard)         │
│                     │                       │
│  • Double Ratchet   │  • ICE/STUN/TURN      │
│  • Server-routed    │  • P2P when possible  │
│  • Store & forward  │  • Opus/VP8 codecs    │
└─────────────────────┴───────────────────────┘
```

### WhatsApp

```
┌─────────────────────────────────────────────┐
│                 WhatsApp                     │
├─────────────────────┬───────────────────────┤
│    Text Messages    │    Voice/Video Calls  │
│    ──────────────   │    ────────────────   │
│    Signal Protocol  │    WebRTC-based       │
│    (licensed)       │    (modified)         │
│                     │                       │
│  • Server-routed    │  • ICE for NAT        │
│  • Cloud backup     │  • Custom TURN infra  │
│  • E2E encrypted    │  • Group calls        │
└─────────────────────┴───────────────────────┘
```

### Telegram

```
┌─────────────────────────────────────────────┐
│                 Telegram                     │
├─────────────────────┬───────────────────────┤
│    Text Messages    │    Voice/Video Calls  │
│    ──────────────   │    ────────────────   │
│    MTProto          │    WebRTC             │
│    (custom)         │    (standard)         │
│                     │                       │
│  • Server-routed    │  • P2P preferred      │
│  • Cloud storage    │  • Relay fallback     │
│  • NOT E2E default! │  • E2E encrypted      │
└─────────────────────┴───────────────────────┘

Note: Telegram text is NOT end-to-end encrypted
by default (only "Secret Chats" are E2E).
```

### Discord

```
┌─────────────────────────────────────────────┐
│                  Discord                     │
├─────────────────────┬───────────────────────┤
│    Text Messages    │    Voice/Video Calls  │
│    ──────────────   │    ────────────────   │
│    Custom protocol  │    WebRTC             │
│    (WebSocket)      │    (modified)         │
│                     │                       │
│  • Server-routed    │  • SFU for groups     │
│  • NOT E2E          │  • NOT E2E            │
│  • Real-time via WS │  • Low latency        │
└─────────────────────┴───────────────────────┘

Note: Discord has NO end-to-end encryption.
```

### CyxChat (Planned Architecture)

```
┌─────────────────────────────────────────────┐
│                  CyxChat                     │
├─────────────────────┬───────────────────────┤
│    Text/Files       │    Voice/Video Calls  │
│    ──────────────   │    ────────────────   │
│    CyxChat Protocol │    WebRTC             │
│    (custom UDP)     │    (standard)         │
│                     │                       │
│  • P2P first        │  • ICE/STUN           │
│  • Relay fallback   │  • Use CyxChat relay  │
│  • Onion routing    │    as TURN fallback   │
│  • Offline queue    │  • Opus/VP8 codecs    │
│  • E2E encrypted    │  • E2E (DTLS-SRTP)    │
└─────────────────────┴───────────────────────┘

Signaling for WebRTC happens over CyxChat protocol.
```

---

## Why This Hybrid Approach?

### Why NOT Use WebRTC for Everything?

| Concern | WebRTC | CyxChat Protocol |
|---------|--------|------------------|
| Text efficiency | Data channels have overhead | Optimized for small messages |
| Onion routing | Not built-in | Native support |
| Offline queue | Not supported | Built-in |
| Simplicity | Complex stack | Minimal |
| Control | Browser API constraints | Full control |
| Metadata | No protection | Onion routing |

### Why NOT Build Custom Audio/Video?

Building real-time media from scratch requires:

```
Audio pipeline:
├── Codec (Opus) encoding/decoding
├── Jitter buffer
├── Packet loss concealment
├── Echo cancellation
├── Noise suppression
├── Automatic gain control
└── Clock synchronization

Video pipeline:
├── Codec (VP8/VP9/H.264) encoding/decoding
├── Resolution adaptation
├── Bandwidth estimation
├── Keyframe requests
├── Frame buffering
└── Lip sync

Time to implement: 2-3 years
Result: Worse than WebRTC
```

WebRTC handles all of this. Every serious app uses it for calls.

---

## CyxChat Call Integration Design

### Signaling via CyxChat Protocol

```
Call Setup Flow:

1. Alice wants to call Bob
2. Alice checks: Is Bob online? (via bootstrap)
3. Alice → Bob: CALL_OFFER (via CyxChat protocol)
   └── Contains: SDP offer (WebRTC session description)
4. Bob → Alice: CALL_ANSWER (via CyxChat protocol)
   └── Contains: SDP answer
5. Exchange ICE candidates (via CyxChat protocol)
6. WebRTC establishes direct media connection
7. Call audio/video flows via WebRTC P2P
8. Call hangup signaled via CyxChat protocol

CyxChat protocol = signaling transport
WebRTC = media transport
```

### Relay Integration

```
CyxChat relay server can also serve as TURN:

Scenario: Both users behind symmetric NAT

1. WebRTC ICE fails direct connection
2. Falls back to TURN relay
3. CyxChat relay acts as TURN server
4. Media flows: Alice → Relay → Bob

Same infrastructure, dual purpose:
├── Text relay (CyxChat protocol)
└── Media relay (TURN for WebRTC)
```

---

## Security Comparison for Calls

| Aspect | CyxChat (planned) | Signal | WhatsApp | Telegram |
|--------|-------------------|--------|----------|----------|
| Signaling encryption | E2E (CyxChat) | E2E | E2E | Server-side |
| Media encryption | DTLS-SRTP | DTLS-SRTP | DTLS-SRTP | SRTP |
| Key verification | Safety numbers | Safety numbers | Security code | Emoji |
| Metadata (who calls) | Bootstrap sees | Server sees | Server sees | Server sees |
| P2P media | When possible | When possible | When possible | When possible |
| Relay | CyxChat relay | Signal TURN | WhatsApp TURN | Telegram TURN |

---

## Summary

| Aspect | Winner | Why |
|--------|--------|-----|
| **Anonymity** | CyxChat/Session | No phone number, onion routing |
| **Ease of Use** | Signal | Largest user base, familiar UX |
| **Offline Mesh** | Meshtastic/Briar | Purpose-built for mesh |
| **Features** | Matrix | Rooms, threads, bridges |
| **Simplicity** | CyxChat | Minimal protocol, clean code |
| **Censorship Resistance** | CyxChat/Briar | No central servers |
| **NAT Traversal** | CyxChat | UDP hole punch + relay fallback |

---

## Conclusion

CyxChat occupies a unique position: **Signal-grade encryption + Tor-like anonymity**, without requiring phone numbers, central servers, or cryptocurrency.

It's not trying to replace Signal for everyday users. It's for those who need:
- True anonymity (journalists, activists, whistleblowers)
- Censorship resistance (users in restrictive countries)
- Self-sovereign communication (no trust in third parties)
- Direct P2P connections without central infrastructure

**The trade-off is clear**: Less convenience, fewer features, smaller network - in exchange for stronger privacy guarantees and architectural resilience.

---

*Document version: 1.2*
*Last updated: February 2026*
