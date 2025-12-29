# Internal DNS for CyxChat

## Purpose

Replace 32-byte cryptographic node IDs with human-readable usernames.

```
Without DNS:
  /send 7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b "hello"

With DNS:
  /send alice.cyx "hello"
```

---

## Design Goals

1. **Human-Readable**: Easy to remember and share usernames
2. **Decentralized**: No central authority controls names
3. **Self-Certifying**: Names prove ownership cryptographically
4. **NAT-Aware**: Include connectivity info (STUN address, relays)
5. **Privacy-Preserving**: Don't leak who you're talking to

---

## Three-Layer Naming System

```
┌─────────────────────────────────────────────────────────────────┐
│  NAMING LAYERS                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Layer 1: Local Petnames (address book)                        │
│  ───────────────────────────────────────                       │
│    "bob" → 0x1234...                                           │
│    "mom" → 0x5678...                                           │
│    User's personal nicknames, stored locally                   │
│    Different users can have different petnames for same person │
│                                                                 │
│  Layer 2: Global Names (DHT registration)                      │
│  ────────────────────────────────────────                      │
│    "alice.cyx" → 0xABCD...                                     │
│    Registered usernames, stored in distributed hash table      │
│    First-come-first-served or reputation-based                 │
│                                                                 │
│  Layer 3: Cryptographic Names (self-certifying)                │
│  ──────────────────────────────────────────────                │
│    "k5xq3v7b.cyx" → derived from public key                    │
│    Always works, no registration needed                        │
│    Like Tor .onion addresses                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Resolution Order

```
User types: "bob"

1. Check local petnames
   Found? → Use that node_id

2. Check local cache
   Found and not expired? → Use cached result

3. Query DHT for "bob.cyx"
   Found? → Verify signature, use result

4. Is it a crypto-name? (looks like "k5xq3v7b.cyx")
   Yes? → Derive node_id directly from name
```

---

## Record Types

### A Record (Address)

Maps name to node ID.

```
"alice.cyx" → {
  node_id: 0xABCD1234...,
  pubkey: 0x1234ABCD...,
  signature: ...          // Proves ownership
}
```

### RELAY Record (Connectivity)

NAT traversal information.

```
"alice.cyx" RELAY → {
  stun_addr: "1.2.3.4:5678",    // Public address from STUN
  relay_nodes: [                 // Fallback relays
    "relay1.cyx",
    "relay2.cyx"
  ],
  last_seen: 1703849600,        // When last online
  online: true                   // Current status
}
```

### SRV Record (Service)

Service discovery.

```
"_storage._cyx.mydata.cyx" → [
  {node_id: 0x1111..., priority: 10},
  {node_id: 0x2222..., priority: 20}
]

"_compute._cyx.myjobs.cyx" → [
  {node_id: 0x3333..., capacity: "high"},
  {node_id: 0x4444..., capacity: "low"}
]
```

### TXT Record (Metadata)

Additional information.

```
"alice.cyx" TXT → {
  display_name: "Alice Smith",
  avatar_hash: "sha256:...",
  capabilities: ["chat", "file", "voice"],
  version: "1.0.0"
}
```

---

## DHT-Based Storage

Names stored in distributed hash table across the network.

### Storage Assignment

```
Name: "alice.cyx"
Hash: SHA256("alice.cyx") = 0x5678...

Stored on nodes whose ID is closest to 0x5678...
(Kademlia-style XOR distance)

Replicated to K nearest nodes (K=3 typical)
```

### Registration Protocol

```
Alice wants to register "alice.cyx":

1. Generate signature: sign(name + pubkey + timestamp, secret_key)

2. Create registration:
   {
     name: "alice.cyx",
     pubkey: 0xABCD...,
     node_id: 0x1234...,    // Derived from pubkey
     timestamp: 1703849600,
     signature: 0x9999...
   }

3. Find nodes responsible for hash("alice.cyx")

4. Send REGISTER message to those nodes

5. Nodes verify:
   • Signature is valid
   • Name not already taken (or owned by same key)
   • Timestamp is recent

6. Store and replicate
```

### Lookup Protocol

```
Bob wants to find "alice.cyx":

1. Compute hash("alice.cyx") = 0x5678...

2. Query nodes closest to 0x5678...

3. Receive registration record

4. Verify:
   • Signature matches pubkey
   • node_id derived correctly from pubkey

5. Cache result with TTL

6. Use node_id and relay info to connect
```

---

## Name Conflict Resolution

### First-Come-First-Served

```
Simple but problematic:
  • Squatters can grab popular names
  • No recourse if someone takes "your" name
```

### Reputation-Based

```
Names require minimum reputation to register:
  • Common names: reputation > 50
  • Short names (< 5 chars): reputation > 80
  • Reserved names: not allowed

Reputation earned through:
  • Network participation
  • Successful transactions
  • Time in network
```

### Stake-Based

```
Deposit tokens to hold name:
  • Popular names require higher deposit
  • Deposit returned when name released
  • Slashed if misbehavior detected
```

### Hybrid (Recommended)

```
1. Crypto-names always available (no conflict possible)
2. Short/common names require reputation OR deposit
3. Long unique names: first-come-first-served
4. Dispute resolution via community voting
```

---

## Privacy Considerations

### Problem: DNS Queries Reveal Intent

```
Alice queries "bob.cyx"
→ DNS nodes learn Alice wants to contact Bob
→ Metadata leak!
```

### Solution: Onion DNS Queries

```
Alice → Onion Circuit → DNS Node

DNS node sees query but not who's asking.
Response travels back through circuit.
```

### Solution: Local Caching

```
Aggressive caching reduces query frequency:
  • Cache for 1 hour (or TTL from record)
  • Prefetch for contacts
  • Background refresh
```

### Solution: Dummy Queries

```
Mix real queries with fake ones:
  • Query random names periodically
  • Makes real queries less distinguishable
  • Traffic analysis resistance
```

---

## DNS Message Types

```c
/* DNS Message Types (0xD0-0xDF) */

#define CYXDNS_MSG_REGISTER        0xD0  /* Register name */
#define CYXDNS_MSG_REGISTER_ACK    0xD1  /* Registration confirmed */
#define CYXDNS_MSG_LOOKUP          0xD2  /* Query name */
#define CYXDNS_MSG_LOOKUP_RESP     0xD3  /* Query response */
#define CYXDNS_MSG_UPDATE          0xD4  /* Update record */
#define CYXDNS_MSG_UPDATE_ACK      0xD5  /* Update confirmed */
#define CYXDNS_MSG_TRANSFER        0xD6  /* Transfer name ownership */
#define CYXDNS_MSG_REVOKE          0xD7  /* Revoke name */
#define CYXDNS_MSG_REPLICATE       0xD8  /* DHT replication */
```

---

## Message Formats

### Registration Request

```
┌────────────────────────────────────────────────────────────┐
│ type (1) │ name_len (1) │ name (var) │ pubkey (32)        │
├────────────────────────────────────────────────────────────┤
│ timestamp (8) │ ttl (4) │ relay_info (var) │ sig (64)     │
└────────────────────────────────────────────────────────────┘
```

### Lookup Request

```
┌────────────────────────────────────────────────────────────┐
│ type (1) │ name_len (1) │ name (var) │ request_id (4)     │
└────────────────────────────────────────────────────────────┘
```

### Lookup Response

```
┌────────────────────────────────────────────────────────────┐
│ type (1) │ request_id (4) │ found (1) │ record (var)      │
└────────────────────────────────────────────────────────────┘

record = {
  name, pubkey, node_id, timestamp, ttl, relay_info, signature
}
```

---

## Integration with NAT Traversal

DNS becomes the rendezvous point for connectivity info:

```
┌─────────────────────────────────────────────────────────────────┐
│  DNS + NAT Integration                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Bob discovers his public address via STUN                  │
│     STUN → Bob: "You're 5.6.7.8:9999"                          │
│                                                                 │
│  2. Bob registers with DNS                                      │
│     "bob.cyx" → {                                              │
│       node_id: 0x1234...,                                      │
│       pubkey: 0xABCD...,                                       │
│       stun_addr: "5.6.7.8:9999",                               │
│       relays: ["relay1.cyx", "relay2.cyx"],                    │
│       online: true                                              │
│     }                                                           │
│                                                                 │
│  3. Alice queries "bob.cyx"                                     │
│     Gets: pubkey + stun_addr + relay fallbacks                 │
│                                                                 │
│  4. Alice attempts connection                                   │
│     Try: UDP hole punch to 5.6.7.8:9999                        │
│     Fail? → Use relay1.cyx                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Presence Tracking

DNS can track online/offline status:

```
Online Detection:
  • Nodes periodically refresh their registration
  • Include current STUN address
  • Set online: true

Offline Detection:
  • Registration not refreshed within TTL
  • Mark as online: false
  • Keep last-known relay info

Query Response:
  {
    ...
    online: false,
    last_seen: 1703849600,
    mailbox: "carol.cyx"    // Where to leave messages
  }
```

---

## Minimal Implementation (Gossip-Based)

For initial version, skip full DHT:

```
Simple Gossip DNS:

1. Every node maintains partial name cache

2. Registration:
   • Broadcast: REGISTER("alice.cyx", pubkey, sig)
   • Neighbors verify and store
   • Gossip to their neighbors

3. Lookup:
   • Check local cache
   • If miss, ask neighbors
   • They check their cache or ask their neighbors

4. Expiration:
   • Entries expire after TTL
   • Must re-register periodically

Good enough for small networks (< 1000 nodes)
Upgrade to full DHT when needed
```

---

## API

```c
/* Create DNS context */
cyxwiz_error_t cyxdns_create(cyxdns_ctx_t **ctx, cyxwiz_router_t *router);

/* Register a name */
cyxwiz_error_t cyxdns_register(
    cyxdns_ctx_t *ctx,
    const char *name,
    const uint8_t *pubkey,
    uint32_t ttl
);

/* Lookup a name */
cyxwiz_error_t cyxdns_lookup(
    cyxdns_ctx_t *ctx,
    const char *name,
    cyxdns_record_t *record_out
);

/* Update relay info */
cyxwiz_error_t cyxdns_update_relay(
    cyxdns_ctx_t *ctx,
    const char *stun_addr,
    const char **relay_nodes,
    size_t relay_count
);

/* Add local petname */
cyxwiz_error_t cyxdns_add_petname(
    cyxdns_ctx_t *ctx,
    const char *petname,
    const cyxwiz_node_id_t *node_id
);
```

---

## Future Enhancements

1. **Subdomains**: "work.alice.cyx", "personal.alice.cyx"
2. **Wildcards**: "*.company.cyx" for organization
3. **Verified Names**: Proof of real-world identity
4. **Name Marketplace**: Buy/sell/rent names
5. **Expiring Names**: Auto-release after inactivity
