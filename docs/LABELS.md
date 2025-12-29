# MPLS-Style Labels for CyxChat

## The Problem

Current onion routing uses 32-byte node IDs at each hop, consuming too much space.

```
Current per-layer overhead:
  next_hop: 32 bytes
  ephemeral_key: 32 bytes
  encryption overhead: 40 bytes
  ─────────────────────────────
  Total: 104 bytes per layer

Payload capacity (250-byte LoRa limit):
  1-hop: 139 bytes
  2-hop: 35 bytes
  3-hop: Not possible!
```

---

## Solution: Short Labels

Replace 32-byte node IDs with 2-byte labels for established connections.

```
Proposed per-layer overhead:
  next_label: 2 bytes
  seq_number: 2 bytes
  encryption overhead: 40 bytes
  ─────────────────────────────
  Total: 44 bytes per layer (60 bytes saved!)

New payload capacity:
  1-hop: 167 bytes (+28)
  2-hop: 123 bytes (+88)
  3-hop: 79 bytes (now possible!)
```

---

## How Labels Work

### Label = Reference to UDP Hole

Each label maps to an established connection:

```
┌─────────────────────────────────────────────────────────────────┐
│  Node B's Label Table                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────┬────────────┬─────────────────────────────────┐  │
│  │ In Label  │ Out Label  │ Connection                      │  │
│  ├───────────┼────────────┼─────────────────────────────────┤  │
│  │    100    │    200     │ UDP hole to Alice (1.2.3.4:567) │  │
│  │    101    │    300     │ UDP hole to Charlie (9.9.9.9:12)│  │
│  │    102    │    150     │ Same peer, different circuit    │  │
│  └───────────┴────────────┴─────────────────────────────────┘  │
│                                                                 │
│  When packet arrives with Label 100:                           │
│    1. Look up in table                                         │
│    2. Decrypt payload                                          │
│    3. Extract next_label (200)                                 │
│    4. Re-encrypt for next hop                                  │
│    5. Send through connection to Alice                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Label Switching (Like MPLS)

```
Alice                Bob                 Charlie              Dave
  │                   │                    │                   │
  │─ Label 100 ──────►│                    │                   │
  │                   │─ Label 200 ───────►│                   │
  │                   │                    │─ Label 300 ──────►│
  │                   │                    │                   │
  │ Bob swaps:        │ Charlie swaps:     │ Dave receives     │
  │ 100 → 200         │ 200 → 300          │ final payload     │
```

---

## Label Distribution Protocol

### Circuit Setup

```
┌─────────────────────────────────────────────────────────────────┐
│  Circuit Setup: Alice → Bob → Charlie                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PHASE 1: Alice ↔ Bob                                          │
│                                                                 │
│  Alice                           Bob                            │
│     │                             │                             │
│     │── CIRCUIT_CREATE ──────────►│                             │
│     │   circuit_id: 0xABCD        │                             │
│     │   dest: Bob                 │                             │
│     │   pubkey: alice_ephemeral   │                             │
│     │                             │                             │
│     │   Bob computes shared_secret = DH(bob, alice_eph)        │
│     │   Bob assigns label 100                                   │
│     │                             │                             │
│     │◄── CIRCUIT_CREATED ─────────│                             │
│     │    label_in: 100            │                             │
│     │    pubkey: bob_ephemeral    │                             │
│     │    mac: HMAC(shared, data)  │                             │
│     │                             │                             │
│  Alice verifies MAC, computes shared_secret                    │
│  Circuit established, use label 100 to Bob                     │
│                                                                 │
│  PHASE 2: Extend to Charlie (through Bob)                      │
│                                                                 │
│  Alice                    Bob                    Charlie        │
│     │                      │                        │           │
│     │── [Label 100] ──────►│                        │           │
│     │   CIRCUIT_EXTEND     │── CIRCUIT_CREATE ─────►│           │
│     │   (encrypted)        │   circuit_id: 0x1234   │           │
│     │   next: Charlie      │   pubkey: bob_eph2     │           │
│     │                      │                        │           │
│     │                      │◄── CIRCUIT_CREATED ────│           │
│     │                      │    label_in: 200       │           │
│     │                      │                        │           │
│     │◄── [Label 100] ──────│                        │           │
│     │    CIRCUIT_EXTENDED  │                        │           │
│     │    label_out: 200    │                        │           │
│                                                                 │
│  Bob's table: 100 → swap to 200 → send to Charlie              │
│  Alice now has 2-hop circuit with labels                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Message Types

```c
/* Label/Circuit Message Types */

#define CYXWIZ_MSG_CIRCUIT_CREATE   0x30  /* Create circuit to peer */
#define CYXWIZ_MSG_CIRCUIT_CREATED  0x31  /* Circuit created, label assigned */
#define CYXWIZ_MSG_CIRCUIT_EXTEND   0x32  /* Extend circuit by one hop */
#define CYXWIZ_MSG_CIRCUIT_EXTENDED 0x33  /* Extension complete */
#define CYXWIZ_MSG_CIRCUIT_DESTROY  0x34  /* Tear down circuit */
#define CYXWIZ_MSG_LABEL_DATA       0x35  /* Data with label header */
```

---

## Packet Format

### Label Data Packet

```
┌────────────────────────────────────────────────────────────────┐
│  CYXWIZ_MSG_LABEL_DATA Packet                                  │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌────────┬────────┬──────────────────────────┬────────────┐  │
│  │ type   │ label  │ encrypted_payload        │ mac        │  │
│  │ 1 byte │ 2 bytes│ variable                 │ 8 bytes    │  │
│  └────────┴────────┴──────────────────────────┴────────────┘  │
│                                                                │
│  encrypted_payload contains:                                   │
│  ┌─────────────┬─────┬──────────────────────────────────────┐ │
│  │ next_label  │ seq │ inner_data                           │ │
│  │ 2 bytes     │ 2B  │ (payload or next encrypted layer)    │ │
│  └─────────────┴─────┴──────────────────────────────────────┘ │
│                                                                │
│  Total overhead per hop: 4 bytes (vs 64 bytes with node IDs)  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Processing at Each Hop

```
1. Receive packet with Label 100
2. Look up label in table → find circuit info
3. Verify MAC with circuit key
4. Check sequence number (replay protection)
5. Decrypt payload → get next_label + inner_data
6. If next_label == 0: deliver to local app
7. Else: build new packet with next_label, forward
```

---

## Security Measures

### Replay Protection

```
┌─────────────────────────────────────────────────────────────────┐
│  Sequence Numbers                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Each circuit maintains:                                        │
│    • send_seq: incremented on each send                        │
│    • recv_seq: last received sequence                          │
│    • recv_window: bitmap of recent sequences                   │
│                                                                 │
│  On receive:                                                    │
│    1. If seq <= recv_seq - 64: DROP (too old)                  │
│    2. If seq in recv_window: DROP (replay)                     │
│    3. Mark seq in window, update recv_seq                      │
│    4. Accept packet                                             │
│                                                                 │
│  Window allows out-of-order delivery (UDP doesn't guarantee    │
│  order) while still detecting replays.                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Label Spoofing Prevention

```
Without MAC:
  Attacker guesses Label 100, sends garbage
  Node forwards garbage (DoS)

With MAC:
  ┌────────┬────────────────────┬────────────┐
  │ Label  │ Encrypted Payload  │ MAC        │
  │ 2 bytes│ N bytes            │ 8 bytes    │
  └────────┴────────────────────┴────────────┘

  MAC = HMAC(circuit_key, label || payload)

  Attacker can't forge valid MAC without circuit_key
  Spoofed packets detected and dropped silently
```

### Label Scanning Prevention

```
Attacker tries labels 0, 1, 2, 3... to find active circuits

Mitigations:
  1. Silent drop (no response to invalid labels)
  2. Rate limiting per source
  3. Random label assignment (not sequential)
  4. Short label lifetime (harder to scan)
```

---

## Label Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│  Label States                                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FREE ──► RESERVED ──► ACTIVE ──► EXPIRING ──► FREE            │
│              │            │           │                         │
│              │            │           └── Grace period (5s)     │
│              │            │               Reject new data       │
│              │            │               Allow retransmits     │
│              │            │                                     │
│              │            └── Normal operation                  │
│              │                Timeout: 60s idle                 │
│              │                                                  │
│              └── During circuit setup                           │
│                  Timeout: 5s                                    │
│                                                                 │
│  After FREE:                                                    │
│    Wait random 5-15s before reuse                              │
│    Prevents stale packets hitting new circuit                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Comparison: Labels vs Full Onion

| Property | Full Onion | Labels | Hybrid |
|----------|------------|--------|--------|
| Payload capacity | Low | High | High |
| Forward secrecy | Per-packet | Per-circuit | Per-circuit |
| Setup overhead | Low | Higher | Higher |
| Path hiding (insider) | Strong | Moderate | Strong |
| Replay protection | Nonce-based | Seq-based | Seq-based |
| Implementation | Current | New | New |

### Hybrid Approach (Recommended)

```
Setup: Full node IDs + ephemeral keys (establish shared secrets)
Data: Labels + encrypted payload (efficient transfer)

Best of both worlds:
  • Strong key exchange during setup
  • Efficient data transfer
  • Per-circuit forward secrecy (acceptable for 60s lifetime)
```

---

## Integration with CyxChat

### For NAT Traversal

```
Label = Reference to UDP Hole

When hole is punched:
  1. Assign label to this connection
  2. Add to label table
  3. Use label for all data through this hole

If hole closes:
  1. Detect via keepalive failure
  2. Mark label as EXPIRING
  3. Re-punch hole
  4. Assign new label
  5. Notify circuits to rebuild
```

### For Chat Messages

```
Alice sends message to Bob (3 hops for privacy):

1. Build circuit: Alice → X → Y → Bob
   Setup establishes labels at each hop

2. Send message:
   ┌─────────────────────────────────────────────────────────┐
   │ [Label 100] [Enc_X( [Label 200] [Enc_Y( [Label 300]    │
   │              [Enc_Bob( "Hello Bob!" )] )] )]           │
   └─────────────────────────────────────────────────────────┘

3. Each hop:
   X: decrypt, see label 200, forward to Y
   Y: decrypt, see label 300, forward to Bob
   Bob: decrypt, see label 0 (final), deliver message

4. Total overhead: 3 × 44 = 132 bytes
   vs current: 3 × 104 = 312 bytes (wouldn't fit!)
```

---

## Data Structures

```c
/* Label entry */
typedef struct {
    uint16_t label_in;           /* Incoming label */
    uint16_t label_out;          /* Outgoing label (next hop) */
    uint32_t circuit_id;         /* Associated circuit */
    uint8_t key[32];             /* Per-hop symmetric key */
    uint32_t send_seq;           /* Send sequence counter */
    uint32_t recv_seq;           /* Receive sequence */
    uint64_t recv_window;        /* Replay window bitmap */
    uint64_t created_at;
    uint64_t last_used;
    uint8_t state;               /* FREE, RESERVED, ACTIVE, EXPIRING */
} cyxwiz_label_entry_t;

/* Label table */
typedef struct {
    cyxwiz_label_entry_t entries[65536];  /* 16-bit label space */
    uint16_t next_label;                   /* Next label to assign */
    size_t active_count;
} cyxwiz_label_table_t;

/* Circuit with labels */
typedef struct {
    uint32_t circuit_id;
    uint8_t hop_count;
    uint16_t labels[CYXWIZ_MAX_ONION_HOPS];  /* Label for each hop */
    uint8_t keys[CYXWIZ_MAX_ONION_HOPS][32]; /* Key for each hop */
    uint64_t created_at;
    bool active;
} cyxwiz_label_circuit_t;
```

---

## API

```c
/* Create label table */
cyxwiz_error_t cyxwiz_label_table_create(cyxwiz_label_table_t **table);

/* Allocate new label */
uint16_t cyxwiz_label_allocate(cyxwiz_label_table_t *table);

/* Free label */
void cyxwiz_label_free(cyxwiz_label_table_t *table, uint16_t label);

/* Set up label mapping */
cyxwiz_error_t cyxwiz_label_set_mapping(
    cyxwiz_label_table_t *table,
    uint16_t label_in,
    uint16_t label_out,
    const uint8_t *key
);

/* Look up label */
cyxwiz_label_entry_t *cyxwiz_label_lookup(
    cyxwiz_label_table_t *table,
    uint16_t label
);

/* Build circuit with labels */
cyxwiz_error_t cyxwiz_label_circuit_build(
    cyxwiz_onion_ctx_t *ctx,
    const cyxwiz_node_id_t *hops,
    uint8_t hop_count,
    cyxwiz_label_circuit_t **circuit_out
);

/* Send via label circuit */
cyxwiz_error_t cyxwiz_label_send(
    cyxwiz_onion_ctx_t *ctx,
    cyxwiz_label_circuit_t *circuit,
    const uint8_t *data,
    size_t len
);
```

---

## Migration Path

```
Phase 1: Add label infrastructure
  • Label table data structures
  • Allocation/deallocation
  • No wire protocol changes

Phase 2: Circuit setup with labels
  • New CIRCUIT_CREATE/CREATED messages
  • Label negotiation
  • Store alongside existing circuits

Phase 3: Label-based data transfer
  • New CYXWIZ_MSG_LABEL_DATA type
  • Modified wrap/unwrap
  • Keep old onion as fallback

Phase 4: Full migration
  • Default to labels for all circuits
  • Remove old onion (optional)
  • Performance optimization
```
