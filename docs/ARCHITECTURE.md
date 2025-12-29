# CyxChat Architecture

## Vision

**"WhatsApp/Signal without servers"**

A fully decentralized, privacy-first chat application built on the CyxWiz protocol.

### Core Principles

- **No Central Server**: All communication is peer-to-peer
- **Any Location**: Works behind NAT, firewalls, mobile networks
- **End-to-End Encrypted**: Only sender and recipient can read messages
- **Local Storage**: Messages stored on device (IMAP4-style), not in cloud
- **P2P File Transfer**: Files sent directly between peers, never stored on servers
- **Offline Support**: Store-and-forward for when recipient is unavailable

---

## Architecture Stack

```
┌────────────────────────────────────────────────────────────┐
│                      CYXCHAT APP                           │
│  • Contact list (petnames + crypto IDs)                    │
│  • Chat UI (messages, groups, files)                       │
│  • Local storage (SQLite + encryption)                     │
└────────────────────────────────────────────────────────────┘
                            │
┌────────────────────────────────────────────────────────────┐
│                   CYXCHAT PROTOCOL                         │
│  • Message types (text, file, presence, typing)            │
│  • Delivery receipts                                       │
│  • Group management                                        │
│  • Multi-device sync                                       │
└────────────────────────────────────────────────────────────┘
                            │
┌────────────────────────────────────────────────────────────┐
│                     CYXWIZ CORE                            │
│  • DNS (username resolution)                               │
│  • NAT traversal (UDP hole punch + relay)                  │
│  • Onion routing (privacy)                                 │
│  • Store-and-forward (offline delivery)                    │
└────────────────────────────────────────────────────────────┘
                            │
┌────────────────────────────────────────────────────────────┐
│                      TRANSPORT                             │
│  • UDP/Internet (primary for mobile/desktop)               │
│  • WiFi Direct (nearby, no internet)                       │
│  • Bluetooth (close range)                                 │
│  • LoRa (rural, emergency)                                 │
└────────────────────────────────────────────────────────────┘
```

---

## Key Technologies

### 1. NAT Traversal

Mobile phones and most desktops are behind NAT routers that block incoming connections.

#### The Problem

```
Alice (192.168.1.5)          Bob (192.168.2.10)
      │                             │
  ┌───┴───┐                     ┌───┴───┐
  │  NAT  │                     │  NAT  │
  │1.2.3.4│                     │5.6.7.8│
  └───────┘                     └───────┘
      │         Internet            │
      └─────────────────────────────┘

Neither can directly reach the other.
NAT blocks unsolicited incoming connections.
```

#### Solution: UDP Hole Punching

```
1. STUN Discovery
   Alice → STUN server: "What's my public IP?"
   STUN → Alice: "You're 1.2.3.4:5678"

2. Exchange via Bootstrap/DNS
   Alice registers: "alice.cyx" → 1.2.3.4:5678
   Bob registers: "bob.cyx" → 5.6.7.8:9012

3. Simultaneous Connection
   Alice → Bob's public address (creates hole in Alice's NAT)
   Bob → Alice's public address (creates hole in Bob's NAT)

4. Direct P2P Communication
   Both NATs now allow traffic through the "holes"
```

#### Fallback: Relay Nodes

When hole punching fails (symmetric NAT, strict firewalls):

```
Alice ──► Relay Node ──► Bob

• Relay sees only encrypted blobs (onion routing)
• Cannot read message content
• Just forwards packets between connections
```

### 2. Internal DNS

Human-readable usernames instead of 32-byte node IDs.

#### Three-Layer Naming

```
Layer 1: Local Petnames (address book)
  "bob" → node_id (your personal nickname)

Layer 2: Global Names (DHT registration)
  "alice.cyx" → node_id (registered username)

Layer 3: Cryptographic Names (self-certifying)
  "k5xq3v7b.cyx" → derived from public key
```

#### DNS Record Types

```
A Record:     "alice.cyx" → node_id
SRV Record:   "_storage._cyx" → [provider1, provider2]
TXT Record:   "alice.cyx" → {pubkey, capabilities}
RELAY Record: "alice.cyx" → {stun_addr, relay_nodes}
```

#### DNS + NAT Integration

```
Bob registers with DNS:
  "bob.cyx" → {
    pubkey: 0x1234...,
    stun_addr: "5.6.7.8:9999",
    relay: ["relay1.cyx", "relay2.cyx"]
  }

Alice queries "bob.cyx":
  1. Gets Bob's STUN address + relay fallback
  2. Tries hole punch to 5.6.7.8:9999
  3. If fails, uses relay1.cyx
```

### 3. MPLS-Style Labels (Efficient Routing)

Replace 32-byte node IDs with 2-byte labels for established connections.

#### Current vs Proposed

```
Current (32-byte node IDs per hop):
  1-hop: 139 bytes payload
  2-hop: 35 bytes payload
  3-hop: Not possible

With Labels (2-byte per hop):
  1-hop: 167 bytes payload (+28)
  2-hop: 123 bytes payload (+88)
  3-hop: 79 bytes payload (now possible!)
```

#### Label Table

```
Each node maintains:
┌───────────┬────────────┬─────────────────────┐
│ In Label  │ Out Label  │ Next Hop (UDP hole) │
├───────────┼────────────┼─────────────────────┤
│    100    │    200     │ 5.6.7.8:9999        │
│    101    │    300     │ 9.9.9.9:1234        │
└───────────┴────────────┴─────────────────────┘
```

---

## Core Scenarios

### Scenario 1: Both Online (Real-time Chat)

```
Alice (mobile, 4G NAT) ←→ Bob (desktop, home NAT)

1. Alice types "bob" in chat
   └── DNS lookup: "bob.cyx" → Bob's node info
       {pubkey, stun_addr, relay_nodes}

2. NAT traversal:
   ├── Try UDP hole punch to Bob's STUN address
   ├── If success: direct P2P connection
   └── If fail: use relay node

3. Send message:
   ├── Encrypt with Bob's pubkey
   ├── Send via established connection
   └── Get delivery receipt

4. Real-time features:
   ├── Typing indicators
   ├── Read receipts
   └── Presence (online/offline)

Latency: ~100-500ms (like normal chat)
```

### Scenario 2: Recipient Offline (Store-and-Forward)

```
Alice online, Bob offline (phone off)

Option A: Friend Nodes
───────────────────────
Bob pre-configures: "If I'm offline, store with Carol"

1. Alice → DNS: "bob.cyx"
2. DNS returns: {offline: true, mailbox: "carol.cyx"}
3. Alice → Carol: "Hold this for Bob" (encrypted for Bob)
4. Carol stores encrypted blob
5. Bob comes online → Carol delivers queued messages

Option B: DHT Mailbox
─────────────────────
1. Alice encrypts message for Bob
2. Store in DHT at key = hash(Bob's pubkey)
3. Multiple nodes store (redundancy)
4. Bob comes online, queries DHT for his mailbox
5. Retrieves and decrypts messages

Option C: CyxCloud Storage
──────────────────────────
Use existing K-of-N threshold storage for mailbox
Already have threshold retrieval in CyxWiz
```

### Scenario 3: File Transfer

```
Alice sends 50MB video to Bob

1. METADATA FIRST
   Alice → Bob: {
     type: FILE_OFFER,
     name: "vacation.mp4",
     size: 52428800,
     hash: sha256(...),
     chunks: 820
   }

2. BOB ACCEPTS
   Bob → Alice: {type: FILE_ACCEPT, resume_from: 0}

3. CHUNKED TRANSFER (64KB chunks, parallel)
   Chunk 0 ──────────────────────────►
   ◄────────────────────────── ACK 0
   Chunk 1 ──────────────────────────►
   ◄────────────────────────── ACK 1
   ... (parallel for speed)

4. VERIFICATION
   Bob computes hash, confirms match

5. RESUME SUPPORT
   If connection drops at chunk 400:
   Bob → Alice: {type: FILE_ACCEPT, resume_from: 400}

NO SERVER STORAGE - direct P2P transfer
```

### Scenario 4: Group Chat

```
Group: "Family" (Alice, Bob, Carol, Dave)

Option A: Sender Fan-out
────────────────────────
Alice sends to each member individually
Simple but requires connection to everyone

Option B: Relay Fan-out
───────────────────────
Group designates relay node (could be group member)
Alice → Relay → [Bob, Carol, Dave]
Better for mobile (saves battery/bandwidth)

Option C: Gossip-based
──────────────────────
Each member forwards to connected members
Most resilient, eventually consistent
```

---

## Local Storage (IMAP4-style)

### Database Schema

```sql
-- SQLite + SQLCipher (encrypted at rest)

CREATE TABLE contacts (
    id TEXT PRIMARY KEY,           -- node_id
    petname TEXT,                  -- local nickname
    display_name TEXT,             -- their chosen name
    pubkey BLOB NOT NULL,          -- X25519 public key
    last_seen INTEGER,             -- timestamp
    status TEXT                    -- online/offline/away
);

CREATE TABLE conversations (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,            -- 'direct' or 'group'
    name TEXT,                     -- group name (null for direct)
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE conversation_participants (
    conversation_id TEXT,
    contact_id TEXT,
    role TEXT,                     -- 'member', 'admin', 'owner'
    joined_at INTEGER,
    PRIMARY KEY (conversation_id, contact_id)
);

CREATE TABLE messages (
    id TEXT PRIMARY KEY,           -- unique message ID
    conversation_id TEXT NOT NULL,
    sender_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    type TEXT NOT NULL,            -- 'text', 'file', 'image', etc.
    content TEXT,                  -- text content (encrypted)
    metadata TEXT,                 -- JSON (file info, etc.)
    delivered INTEGER DEFAULT 0,   -- delivery receipt received
    read INTEGER DEFAULT 0,        -- read receipt received
    local_path TEXT,               -- local file path (for attachments)
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

-- IMAP4-style folders
CREATE TABLE folders (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INTEGER,
    FOREIGN KEY (parent_id) REFERENCES folders(id)
);

CREATE TABLE message_folders (
    message_id TEXT,
    folder_id INTEGER,
    PRIMARY KEY (message_id, folder_id)
);

-- Full-text search
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    content=messages,
    content_rowid=rowid
);
```

### Default Folders

- **Inbox**: All incoming messages
- **Sent**: Outgoing messages
- **Archive**: Archived conversations
- **Starred**: Important messages
- **Trash**: Deleted (before permanent deletion)

---

## Multi-Device Sync

```
Alice has: Phone + Desktop + Tablet

Option A: Same Identity (shared keypair)
────────────────────────────────────────
All devices use same keypair
Simpler but: compromised device = all compromised

Option B: Linked Devices (recommended)
──────────────────────────────────────
Each device has own keypair
Master key links them
Can revoke individual devices

Sync Protocol:
──────────────
1. Device comes online
2. Connects to other devices (P2P via CyxWiz)
3. Exchange sync state:
   {last_sync: timestamp, vector_clock: {...}}
4. Delta sync - only transfer missing messages
5. Conflict resolution: vector clock based

┌─────────┐         ┌─────────┐         ┌─────────┐
│  Phone  │◄───────►│ Desktop │◄───────►│ Tablet  │
└─────────┘   P2P   └─────────┘   P2P   └─────────┘

All stay in sync - no server needed
```

---

## Message Types

```c
/* CyxChat Message Types (0xC0-0xCF) */

/* Basic Messages */
#define CYXCHAT_MSG_TEXT           0xC0  /* Text message */
#define CYXCHAT_MSG_FILE_OFFER     0xC1  /* File transfer offer */
#define CYXCHAT_MSG_FILE_ACCEPT    0xC2  /* Accept file transfer */
#define CYXCHAT_MSG_FILE_CHUNK     0xC3  /* File data chunk */
#define CYXCHAT_MSG_FILE_ACK       0xC4  /* Chunk acknowledgment */
#define CYXCHAT_MSG_FILE_COMPLETE  0xC5  /* Transfer complete */

/* Status Messages */
#define CYXCHAT_MSG_DELIVERED      0xC6  /* Delivery receipt */
#define CYXCHAT_MSG_READ           0xC7  /* Read receipt */
#define CYXCHAT_MSG_TYPING         0xC8  /* Typing indicator */
#define CYXCHAT_MSG_PRESENCE       0xC9  /* Online/offline/away */

/* Group Messages */
#define CYXCHAT_MSG_GROUP_CREATE   0xCA  /* Create group */
#define CYXCHAT_MSG_GROUP_INVITE   0xCB  /* Invite to group */
#define CYXCHAT_MSG_GROUP_LEAVE    0xCC  /* Leave group */
#define CYXCHAT_MSG_GROUP_MSG      0xCD  /* Group message */

/* Sync Messages */
#define CYXCHAT_MSG_SYNC_REQ       0xCE  /* Request sync */
#define CYXCHAT_MSG_SYNC_DATA      0xCF  /* Sync data payload */
```

---

## Mobile Considerations

### Challenges

| Challenge | Solution |
|-----------|----------|
| Battery drain | Lightweight presence pings, store-forward |
| Network switching (WiFi ↔ 4G) | Re-establish holes on network change |
| Background restrictions | Wake on incoming via relay ping |
| Metered data | Efficient protocols, defer large files to WiFi |
| Limited storage | Auto-cleanup, stream large files |

### Push Notifications (Without Central Server)

```
Option A: Friend Relay Network
──────────────────────────────
Alice designates "always-on" friends as relay nodes.

1. Bob → Alice (offline)
2. Bob checks DNS → Alice's relay is Carol
3. Bob → Carol: "ping Alice"
4. Carol → FCM/APNs: "wake Alice app"
5. Alice wakes → connects to Bob

Hybrid: Uses platform push but relay is trusted friend

Option B: Pure P2P (no push)
────────────────────────────
Accept that offline = delayed delivery
Messages queue at sender or mailbox nodes
Retrieved on next app open
Like email (not instant, but works)

Option C: Community Relay Service
─────────────────────────────────
Volunteer-run relay nodes
Hold encrypted messages for offline users
Optional push integration (user choice)
Decentralized but with infrastructure
```

---

## Security Model

### Encryption

| Layer | Algorithm | Purpose |
|-------|-----------|---------|
| Transport | XChaCha20-Poly1305 | Per-hop encryption |
| Message | X25519 + XChaCha20 | End-to-end encryption |
| Storage | SQLCipher (AES-256) | Local database encryption |
| Files | XChaCha20-Poly1305 | File transfer encryption |

### Key Management

```
Identity Key (long-term):
  • X25519 keypair
  • Used for identity verification
  • Stored encrypted with user passphrase

Session Keys (ephemeral):
  • Generated per conversation
  • Rotated periodically (forward secrecy)
  • Derived via Double Ratchet (like Signal)

Device Keys (per-device):
  • Each device has own keypair
  • Linked to identity key
  • Can be revoked individually
```

### Privacy Features

- **Onion Routing**: Optional for sensitive messages
- **Metadata Protection**: DNS queries via onion routes
- **Forward Secrecy**: Key rotation limits exposure
- **Deniability**: No cryptographic proof of authorship

---

## Implementation Roadmap

### Phase 1: Core Connectivity
- [ ] UDP transport with STUN (NAT discovery)
- [ ] UDP hole punching implementation
- [ ] Relay node fallback
- [ ] Connection keep-alive

### Phase 2: Naming & Discovery
- [ ] Internal DNS (gossip-based)
- [ ] Username registration
- [ ] Presence tracking
- [ ] Relay node discovery

### Phase 3: Chat Protocol
- [ ] Message types (text, file, status)
- [ ] Delivery/read receipts
- [ ] Store-and-forward (mailbox)
- [ ] Group messaging

### Phase 4: File Transfer
- [ ] Chunked transfer protocol
- [ ] Resume support
- [ ] Hash verification
- [ ] Progress tracking

### Phase 5: Local Storage
- [ ] SQLite + SQLCipher integration
- [ ] Message/conversation schema
- [ ] Full-text search (FTS5)
- [ ] Folder management

### Phase 6: Multi-Device
- [ ] Device linking protocol
- [ ] Sync state management
- [ ] Delta sync implementation
- [ ] Conflict resolution

### Phase 7: Mobile/Desktop Apps
- [ ] Cross-platform UI framework
- [ ] Platform-specific integrations
- [ ] Notification handling
- [ ] Background sync

---

## Design Decisions (To Be Made)

### Offline Delivery
- [ ] Friend relays only (more private)
- [ ] Community relays (more reliable)
- [ ] DHT mailbox (most decentralized)
- [ ] Hybrid (user chooses)

### Push Notifications
- [ ] No push (pure P2P, accept delay)
- [ ] Hybrid (relay can trigger push)
- [ ] User's own server (self-hosted)

### Identity Model
- [ ] Single keypair (simple)
- [ ] Per-device keys (more secure)
- [ ] Hierarchical (master + device keys)

### Group Architecture
- [ ] Sender fan-out
- [ ] Designated relay
- [ ] Gossip-based

---

## Related Documents

- [CyxWiz Routing](../cyxwiz-routing.md) - Core routing protocol
- [CyxWiz Messaging](../cyxwiz-messaging.md) - Message protocol details
- [NAT Traversal](./NAT-TRAVERSAL.md) - UDP hole punching details
- [Internal DNS](./DNS.md) - Naming system design
- [Labels](./LABELS.md) - MPLS-style routing optimization
