# CyxMail - Decentralized Email for CyxWiz

## Why Email Works Here

Our store-and-forward architecture is **exactly how email works**:

```
Traditional Email:
  Alice → SMTP Server → Bob's IMAP Server → Bob retrieves

CyxMail:
  Alice → Mailbox Node(s) → Bob retrieves when online

Same concept, no central servers!
```

---

## CyxMail vs CyxChat

| Feature | CyxChat | CyxMail |
|---------|---------|---------|
| Real-time | Yes (when online) | No (async) |
| Offline delivery | Via mailbox | Native |
| Message size | Small (~1KB) | Large (attachments) |
| Threading | Conversations | Email threads |
| Metadata | Minimal | Subject, headers, etc. |
| Format | Simple text/file | MIME-like structured |
| Use case | Instant messaging | Formal communication |

**Key insight**: They share the same infrastructure but different protocols on top.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       CYXMAIL STACK                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    EMAIL CLIENT                           │ │
│  │  • Compose/read emails                                    │ │
│  │  • Folders (Inbox, Sent, Drafts, etc.)                   │ │
│  │  • Search, filters, labels                                │ │
│  │  • Contact integration                                    │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   CYXMAIL PROTOCOL                        │ │
│  │  • MIME-like message format                               │ │
│  │  • Attachments (chunked)                                  │ │
│  │  • Threading (References header)                          │ │
│  │  • Delivery/read receipts                                 │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   MAILBOX LAYER                           │ │
│  │  • Store-and-forward nodes                                │ │
│  │  • DHT-based mailbox                                      │ │
│  │  • Friend relay mailboxes                                 │ │
│  │  • Retrieval protocol                                     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    CYXWIZ CORE                            │ │
│  │  • Encryption, routing, NAT traversal                     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Email Address Format

```
Traditional:  alice@gmail.com
CyxMail:      alice@cyx  or  alice.cyx

Components:
  alice       → Username (registered in DNS)
  @cyx / .cyx → CyxWiz network identifier

Full address with routing hint:
  alice.cyx via relay.cyx
  (Use relay.cyx if direct delivery fails)
```

---

## Message Format

### MIME-like Structure

```
┌─────────────────────────────────────────────────────────────────┐
│  CyxMail Message                                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Headers:                                                       │
│  ─────────                                                      │
│  Message-ID: <unique-id@cyx>                                   │
│  From: alice.cyx                                                │
│  To: bob.cyx, carol.cyx                                        │
│  Cc: dave.cyx                                                   │
│  Subject: Project Update                                        │
│  Date: 2024-01-15T10:30:00Z                                    │
│  In-Reply-To: <previous-id@cyx>                                │
│  References: <thread-root@cyx> <previous-id@cyx>               │
│  Content-Type: multipart/mixed                                  │
│                                                                 │
│  Body Parts:                                                    │
│  ───────────                                                    │
│  Part 1: text/plain                                             │
│    "Here's the project update..."                              │
│                                                                 │
│  Part 2: application/pdf                                        │
│    Name: report.pdf                                             │
│    Size: 1048576                                                │
│    Hash: sha256:abcd1234...                                     │
│    (Chunked transfer or inline if small)                        │
│                                                                 │
│  Signature:                                                     │
│  ──────────                                                     │
│  Ed25519 signature of headers + body                           │
│                                                                 │
│  Encryption:                                                    │
│  ───────────                                                    │
│  Entire message encrypted to recipient's pubkey                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Wire Format

```c
typedef struct {
    uint8_t version;           /* Protocol version */
    uint32_t message_id;       /* Unique ID (or hash) */
    uint8_t from[32];          /* Sender node ID */
    uint8_t to_count;          /* Number of recipients */
    /* cyxwiz_node_id_t to[] follows */
    uint16_t subject_len;
    /* char subject[] follows */
    uint64_t timestamp;
    uint32_t in_reply_to;      /* Parent message ID */
    uint16_t body_len;
    /* body follows */
    uint8_t attachment_count;
    /* attachments follow */
    uint8_t signature[64];     /* Ed25519 signature */
} cyxmail_message_t;

typedef struct {
    uint8_t type;              /* MIME type enum */
    uint16_t name_len;
    /* char name[] follows */
    uint32_t size;
    uint8_t hash[32];          /* SHA256 of content */
    /* inline data or chunk references */
} cyxmail_attachment_t;
```

---

## Mailbox System

### Option 1: Friend Mailboxes

```
┌─────────────────────────────────────────────────────────────────┐
│  Friend Mailbox                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Bob configures: "Carol is my mailbox"                         │
│  Carol agrees to store Bob's mail when he's offline            │
│                                                                 │
│  DNS record for bob.cyx:                                        │
│  {                                                              │
│    node_id: 0x1234...,                                         │
│    mailbox: "carol.cyx",                                       │
│    online: false                                                │
│  }                                                              │
│                                                                 │
│  Alice sends email to bob.cyx:                                  │
│  1. Query DNS → Bob offline, mailbox is Carol                  │
│  2. Encrypt message for Bob (not Carol!)                       │
│  3. Send to Carol: "Store this for Bob"                        │
│  4. Carol stores encrypted blob                                │
│  5. Bob comes online → queries Carol for mail                  │
│  6. Carol delivers, Bob decrypts                               │
│                                                                 │
│  Carol cannot read the email (encrypted for Bob)               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Option 2: DHT Mailboxes

```
┌─────────────────────────────────────────────────────────────────┐
│  DHT-Based Mailbox                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Mailbox location = hash(recipient_pubkey)                     │
│                                                                 │
│  Sending:                                                       │
│  1. Alice computes: mailbox_key = hash(Bob's pubkey)           │
│  2. Find nodes responsible for mailbox_key                     │
│  3. Store encrypted message at those nodes                     │
│                                                                 │
│  Retrieving:                                                    │
│  1. Bob computes: mailbox_key = hash(own pubkey)               │
│  2. Query nodes responsible for mailbox_key                    │
│  3. Retrieve and decrypt messages                              │
│  4. Send deletion request (optional)                           │
│                                                                 │
│  Redundancy:                                                    │
│  • Store at K nearest nodes (K=3)                              │
│  • Any one can deliver                                         │
│  • Replication as nodes join/leave                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Option 3: CyxCloud Mailbox (Use Existing Storage)

```
┌─────────────────────────────────────────────────────────────────┐
│  CyxCloud-Based Mailbox                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Reuse existing K-of-N threshold storage!                      │
│                                                                 │
│  Sending:                                                       │
│  1. Encrypt message for Bob                                    │
│  2. Split into shares (3-of-5)                                 │
│  3. Store shares with storage providers                        │
│  4. Send Bob the storage_id (via DNS or direct)                │
│                                                                 │
│  Retrieving:                                                    │
│  1. Bob retrieves any 3 shares                                 │
│  2. Reconstruct message                                        │
│  3. Decrypt with private key                                   │
│                                                                 │
│  Benefits:                                                      │
│  • Already implemented                                          │
│  • Redundant (tolerates failures)                              │
│  • Encrypted (threshold + pubkey)                              │
│  • Paid storage (incentivized)                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Large Attachments

### Chunked Storage

```
┌─────────────────────────────────────────────────────────────────┐
│  10MB PDF Attachment                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. SPLIT INTO CHUNKS                                          │
│     Chunk 0: 64KB → hash0                                      │
│     Chunk 1: 64KB → hash1                                      │
│     ...                                                         │
│     Chunk 159: remaining → hash159                             │
│                                                                 │
│  2. STORE CHUNKS (via CyxCloud or direct)                      │
│     Store each chunk, get storage_id                           │
│                                                                 │
│  3. MESSAGE CONTAINS MANIFEST                                   │
│     {                                                           │
│       name: "report.pdf",                                      │
│       size: 10485760,                                          │
│       hash: sha256(full file),                                 │
│       chunks: [                                                │
│         {id: storage_id_0, hash: hash0},                       │
│         {id: storage_id_1, hash: hash1},                       │
│         ...                                                    │
│       ]                                                         │
│     }                                                           │
│                                                                 │
│  4. RECIPIENT RETRIEVES                                        │
│     Download chunks (parallel)                                  │
│     Verify individual hashes                                   │
│     Assemble file                                               │
│     Verify full hash                                            │
│                                                                 │
│  Inline option for small attachments (< 64KB)                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Direct P2P Transfer (Both Online)

```
If both parties online, skip storage:

1. Email contains attachment reference (not data)
2. Recipient requests direct transfer
3. P2P chunked transfer (like CyxChat file transfer)
4. Faster, no storage costs
```

---

## Retrieval Protocol (IMAP4-style)

### Commands

```
┌─────────────────────────────────────────────────────────────────┐
│  CyxMail Retrieval Protocol                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LIST                                                           │
│    Request: {command: LIST, folder: "INBOX"}                   │
│    Response: [{id, from, subject, date, size, flags}, ...]     │
│                                                                 │
│  FETCH                                                          │
│    Request: {command: FETCH, id: message_id, parts: [HEADERS]} │
│    Response: {headers: {...}}                                   │
│                                                                 │
│    Request: {command: FETCH, id: message_id, parts: [BODY]}   │
│    Response: {body: "..."}                                      │
│                                                                 │
│    Request: {command: FETCH, id: message_id, parts: [ATT:0]}  │
│    Response: {attachment: chunk_manifest}                       │
│                                                                 │
│  STORE (flags)                                                  │
│    Request: {command: STORE, id: message_id, flags: [SEEN]}   │
│    Response: {ok: true}                                         │
│                                                                 │
│  DELETE                                                         │
│    Request: {command: DELETE, id: message_id}                  │
│    Response: {ok: true}                                         │
│                                                                 │
│  MOVE                                                           │
│    Request: {command: MOVE, id: message_id, folder: "Archive"}│
│    Response: {ok: true}                                         │
│                                                                 │
│  SEARCH                                                         │
│    Request: {command: SEARCH, query: "from:alice subject:test"}│
│    Response: [message_id, ...]                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Flags

```
SEEN      - Message has been read
ANSWERED  - Reply has been sent
FLAGGED   - Marked as important/starred
DELETED   - Marked for deletion
DRAFT     - Saved as draft
```

---

## Folders (Local Storage)

```sql
-- Local SQLite database

CREATE TABLE folders (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INTEGER,
    type TEXT,  -- 'system' or 'user'
    FOREIGN KEY (parent_id) REFERENCES folders(id)
);

-- Default folders
INSERT INTO folders (name, type) VALUES
    ('INBOX', 'system'),
    ('Sent', 'system'),
    ('Drafts', 'system'),
    ('Archive', 'system'),
    ('Trash', 'system'),
    ('Spam', 'system');

CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    folder_id INTEGER NOT NULL,
    from_addr TEXT NOT NULL,
    to_addrs TEXT NOT NULL,  -- JSON array
    cc_addrs TEXT,
    subject TEXT,
    date INTEGER NOT NULL,
    in_reply_to TEXT,
    thread_id TEXT,
    body_text TEXT,
    body_html TEXT,
    flags INTEGER DEFAULT 0,
    size INTEGER,
    FOREIGN KEY (folder_id) REFERENCES folders(id)
);

CREATE TABLE attachments (
    id INTEGER PRIMARY KEY,
    message_id TEXT NOT NULL,
    name TEXT NOT NULL,
    mime_type TEXT,
    size INTEGER,
    hash TEXT,
    local_path TEXT,  -- NULL if not downloaded
    storage_manifest TEXT,  -- JSON chunk info
    FOREIGN KEY (message_id) REFERENCES messages(id)
);

-- Full-text search
CREATE VIRTUAL TABLE messages_fts USING fts5(
    subject, body_text,
    content=messages
);
```

---

## Threading

### Email Threads (References Header)

```
Original email:
  Message-ID: <msg1@cyx>
  Subject: Project Discussion

Reply:
  Message-ID: <msg2@cyx>
  In-Reply-To: <msg1@cyx>
  References: <msg1@cyx>
  Subject: Re: Project Discussion

Reply to reply:
  Message-ID: <msg3@cyx>
  In-Reply-To: <msg2@cyx>
  References: <msg1@cyx> <msg2@cyx>
  Subject: Re: Project Discussion

Thread structure:
  msg1 (root)
    └── msg2
        └── msg3
```

### Thread Grouping

```sql
-- Compute thread_id from References
-- All messages with same root are in same thread

UPDATE messages
SET thread_id = (
    SELECT MIN(ref) FROM (
        SELECT message_id as ref
        UNION
        SELECT value FROM json_each(references)
    )
)
WHERE thread_id IS NULL;
```

---

## Encryption

### End-to-End Encryption

```
┌─────────────────────────────────────────────────────────────────┐
│  Message Encryption                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Generate ephemeral X25519 keypair                          │
│                                                                 │
│  2. For each recipient:                                         │
│     shared_secret = ECDH(ephemeral_secret, recipient_pubkey)   │
│     message_key = HKDF(shared_secret, "cyxmail-message-key")   │
│                                                                 │
│  3. Encrypt message body + attachments:                         │
│     ciphertext = XChaCha20-Poly1305(plaintext, message_key)    │
│                                                                 │
│  4. Package:                                                    │
│     {                                                           │
│       ephemeral_pubkey: ...,                                   │
│       encrypted_keys: [                                         │
│         {recipient: bob.cyx, key: encrypt(msg_key, bob_pk)},   │
│         {recipient: carol.cyx, key: encrypt(msg_key, carol_pk)}│
│       ],                                                        │
│       ciphertext: ...                                           │
│     }                                                           │
│                                                                 │
│  5. Each recipient can decrypt with their private key          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Signature

```
Sign with sender's Ed25519 key:
  signature = Ed25519.sign(hash(headers + body), sender_sk)

Recipient verifies:
  Ed25519.verify(signature, hash(headers + body), sender_pk)

Proves:
  • Message is from claimed sender
  • Message hasn't been modified
```

---

## Spam Prevention

Without central servers, spam is harder to control:

### Reputation-Based

```
• Messages from unknown senders go to review queue
• Accept from contacts automatically
• Build sender reputation over time
• Share reputation data with trusted peers
```

### Proof-of-Work

```
Sender must compute PoW for each message:
  find nonce where hash(message || nonce) < difficulty

Difficulty based on:
  • Sender reputation (low rep = harder PoW)
  • Number of recipients (more = harder)
  • Message size (bigger = harder)

Makes mass spam expensive
```

### Social Graph

```
• Messages from friends-of-friends get priority
• Unknown senders can request introduction
• Web of trust for sender verification
```

---

## Message Types

```c
/* CyxMail Message Types (0xE0-0xEF) */

#define CYXMAIL_MSG_SEND           0xE0  /* Send email to mailbox */
#define CYXMAIL_MSG_SEND_ACK       0xE1  /* Mailbox accepted */
#define CYXMAIL_MSG_LIST           0xE2  /* List mailbox contents */
#define CYXMAIL_MSG_LIST_RESP      0xE3  /* Mailbox listing */
#define CYXMAIL_MSG_FETCH          0xE4  /* Retrieve message */
#define CYXMAIL_MSG_FETCH_RESP     0xE5  /* Message content */
#define CYXMAIL_MSG_DELETE         0xE6  /* Delete from mailbox */
#define CYXMAIL_MSG_DELETE_ACK     0xE7  /* Deletion confirmed */
#define CYXMAIL_MSG_NOTIFY         0xE8  /* New mail notification */
#define CYXMAIL_MSG_RECEIPT        0xE9  /* Delivery/read receipt */
#define CYXMAIL_MSG_BOUNCE         0xEA  /* Delivery failed */
```

---

## Delivery Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Email Delivery: Alice → Bob                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. COMPOSE                                                     │
│     Alice writes email, adds attachments                       │
│     Client generates Message-ID                                │
│                                                                 │
│  2. RESOLVE RECIPIENT                                          │
│     Query DNS: bob.cyx → {node_id, pubkey, mailbox, online}   │
│                                                                 │
│  3. ENCRYPT                                                     │
│     Encrypt message body for Bob's pubkey                      │
│     Sign with Alice's private key                              │
│                                                                 │
│  4. DELIVER                                                     │
│     If Bob online:                                              │
│       → Direct delivery via P2P                                │
│     If Bob offline:                                             │
│       → Store in Bob's mailbox (friend/DHT/CyxCloud)          │
│                                                                 │
│  5. STORE ATTACHMENTS (if large)                               │
│     Upload chunks to CyxCloud                                  │
│     Include manifest in message                                │
│                                                                 │
│  6. NOTIFY (optional)                                          │
│     If Bob has push relay, trigger notification               │
│                                                                 │
│  7. RETRIEVE                                                    │
│     Bob comes online                                            │
│     Queries mailbox → receives message list                    │
│     Fetches new messages                                       │
│     Downloads attachments on demand                            │
│                                                                 │
│  8. RECEIPTS (optional)                                        │
│     Bob's client sends delivery receipt                        │
│     When read, sends read receipt                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Integration with CyxChat

```
┌─────────────────────────────────────────────────────────────────┐
│  Unified Messaging                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Same contact can be reached via:                              │
│    • CyxChat (instant messaging)                               │
│    • CyxMail (email)                                           │
│                                                                 │
│  Shared infrastructure:                                         │
│    • DNS (same username resolution)                            │
│    • NAT traversal (same UDP holes)                            │
│    • Encryption (same keys)                                    │
│    • Mailbox (same store-forward)                              │
│                                                                 │
│  UI can present unified inbox:                                  │
│    • Chat messages                                              │
│    • Emails                                                     │
│    • Files shared                                               │
│    All from same contact in one thread                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Roadmap

### Phase 1: Basic Email
- [ ] Message format (headers, body, signature)
- [ ] Send to online recipient (direct)
- [ ] Local storage (SQLite)
- [ ] Basic UI (compose, read)

### Phase 2: Mailbox
- [ ] Friend-based mailbox
- [ ] DHT-based mailbox
- [ ] Retrieval protocol
- [ ] Offline delivery

### Phase 3: Attachments
- [ ] Inline small attachments
- [ ] Chunked large attachments
- [ ] CyxCloud integration
- [ ] Download on demand

### Phase 4: Advanced Features
- [ ] Threading
- [ ] Search (FTS)
- [ ] Folders and labels
- [ ] Filters and rules
- [ ] Spam prevention
