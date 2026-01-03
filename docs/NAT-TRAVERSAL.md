# NAT Traversal for CyxChat

## The Problem

Most devices are behind NAT (Network Address Translation) routers that block incoming connections.

```
Alice (192.168.1.5)                    Bob (192.168.2.10)
      │                                       │
  ┌───┴───┐                               ┌───┴───┐
  │  NAT  │                               │  NAT  │
  │Router │                               │Router │
  │1.2.3.4│                               │5.6.7.8│
  └───┬───┘                               └───┬───┘
      │              Internet                 │
      └───────────────────────────────────────┘

Problem:
• Alice knows her IP as 192.168.1.5 (private, not routable)
• Bob knows his IP as 192.168.2.10 (private, not routable)
• Neither can directly reach each other
• NAT blocks incoming connections by default
```

---

## How NAT Works

When Alice sends a packet outbound:

```
1. Alice sends UDP from 192.168.1.5:12345 to 5.6.7.8:9999

2. NAT router:
   • Rewrites source: 192.168.1.5:12345 → 1.2.3.4:54321
   • Creates mapping table entry:

   ┌─────────────────────────────────────────────────────────┐
   │ Internal: 192.168.1.5:12345 → External: 1.2.3.4:54321  │
   │ Destination: 5.6.7.8:9999                              │
   │ Timeout: 30 seconds                                     │
   └─────────────────────────────────────────────────────────┘

3. NAT will now accept replies FROM 5.6.7.8 TO 1.2.3.4:54321

This mapping entry is the "hole" - an exception that allows traffic through.
```

---

## Solution: STUN + UDP Hole Punching

### Step 1: STUN Discovery

STUN (Session Traversal Utilities for NAT) helps nodes discover their public address.

```
Alice                           STUN Server
  │                          (stun.l.google.com:19302)
  │                                   │
  │─── Binding Request ──────────────►│
  │                                   │
  │◄── Binding Response ──────────────│
  │    "You're 1.2.3.4:54321"        │
  │                                   │

Alice now knows:
• Public IP: 1.2.3.4
• Public Port: 54321 (assigned by NAT)
```

### Step 2: Exchange via Bootstrap/DNS

Both parties share their public addresses:

```
Alice             Bootstrap/DNS              Bob
  │                    │                      │
  │── Register ───────►│                      │
  │   1.2.3.4:54321    │                      │
  │                    │◄── Register ─────────│
  │                    │    5.6.7.8:9012      │
  │                    │                      │
  │◄── Peer List ──────│                      │
  │   Bob@5.6.7.8:9012 │                      │
```

### Step 3: UDP Hole Punching

Both sides send packets simultaneously to create holes:

```
Timeline:

T=0    Alice sends UDP to 5.6.7.8:9012
       → Alice's NAT creates hole: "expect reply from 5.6.7.8"
       → Packet arrives at Bob's NAT but is DROPPED (no hole yet)

T=0    Bob sends UDP to 1.2.3.4:54321
       → Bob's NAT creates hole: "expect reply from 1.2.3.4"
       → Packet arrives at Alice's NAT but is DROPPED

T=100ms Alice sends again to Bob
        → Bob's NAT now HAS a hole (from Bob's outgoing packet)
        → Packet GETS THROUGH!

T=100ms Bob sends again to Alice
        → Alice's NAT has a hole
        → Packet GETS THROUGH!

Connection established!
```

### Visual Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     UDP Hole Punching                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Alice's NAT                              Bob's NAT             │
│  ┌──────────────────┐                    ┌──────────────────┐  │
│  │ Mapping Table:   │                    │ Mapping Table:   │  │
│  │                  │                    │                  │  │
│  │ Internal → Ext   │                    │ Internal → Ext   │  │
│  │ .1.5:123 → :5432 │                    │ .2.10:456 → :901 │  │
│  │ Dest: 5.6.7.8    │                    │ Dest: 1.2.3.4    │  │
│  │                  │                    │                  │  │
│  │ "Allow traffic   │                    │ "Allow traffic   │  │
│  │  from 5.6.7.8"   │                    │  from 1.2.3.4"   │  │
│  └──────────────────┘                    └──────────────────┘  │
│           │                                      │              │
│           │        ◄──── Both holes open ────►   │              │
│           │                                      │              │
│           └──────── Direct P2P traffic ──────────┘              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## NAT Types and Success Rates

| NAT Type | Behavior | Punch Success |
|----------|----------|---------------|
| **Full Cone** | Same external port for all destinations | ~100% |
| **Restricted Cone** | Allows any port from known IP | ~90% |
| **Port Restricted** | Must match exact IP:port | ~80% |
| **Symmetric** | Different port per destination | ~30-60% |

### The Symmetric NAT Problem

```
With symmetric NAT, router assigns DIFFERENT port for each destination:

Alice → STUN Server:  gets port 50001
Alice → Bob:          gets port 50002 (DIFFERENT!)

1. Alice asks STUN: "What's my public address?"
   STUN says: "You're 1.2.3.4:50001"

2. Alice tells Bob: "Reach me at 1.2.3.4:50001"

3. Bob punches toward 1.2.3.4:50001

4. But Alice's hole for Bob is at 1.2.3.4:50002!

   Bob's packets → 1.2.3.4:50001 → DROPPED (wrong port)
```

### Solutions for Symmetric NAT

**1. Port Prediction**
```
Some NATs increment ports predictably:
  Alice → STUN1: port 50001
  Alice → STUN2: port 50002
  Alice → STUN3: port 50003

Predict: Alice → Bob will use port 50004
Bob tries 50004, 50005, 50006...
Success rate: ~30-40%
```

**2. Birthday Attack (Brute Force)**
```
Both sides try many ports:
  Alice tries: 40000, 40001, 40002, ... (100 ports)
  Bob tries:   40000, 40001, 40002, ... (100 ports)

With ~256 ports each → ~90% collision chance
Slow but works
```

**3. Relay Fallback (Guaranteed)**
```
Alice ──► Relay Node ──► Bob

Both connect TO the relay (outbound)
Relay forwards packets between them
Works with any NAT type
```

---

## Hole Lifetime and Keep-Alive

NAT mappings expire after inactivity (30-120 seconds typically).

```
Solution: Keep-alive packets

Every 15-25 seconds:
  Alice → Bob: PING (small packet)
  Bob → Alice: PONG

If hole closes → must re-punch
```

---

## Implementation for CyxChat

### STUN Servers

```c
static const char* stun_servers[] = {
    "stun.l.google.com:19302",
    "stun.cloudflare.com:3478",
    "stun1.l.google.com:19302",
    "stun2.l.google.com:19302",
    NULL
};
```

### Connection Attempt Sequence

```
1. Try direct hole punch (works ~80% of time)
   ↓ fail
2. Try port prediction (works ~30% for symmetric)
   ↓ fail
3. Try UPnP/NAT-PMP (works ~40% of home routers)
   ↓ fail
4. Use relay node (always works, still encrypted)

Total success: ~95%+
```

### Relay Fallback

```
┌─────────────────────────────────────────────────────────────┐
│  Relay Fallback                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Alice                 Relay Node                     Bob   │
│  (Symmetric NAT)       (Public IP)           (Any NAT)     │
│       │                     │                     │        │
│       │─── outbound ───────►│                     │        │
│       │     (creates hole)  │◄─── outbound ───────│        │
│       │                     │     (creates hole)  │        │
│       │                     │                     │        │
│       │◄────── relay ───────┼─────────────────────│        │
│       │────────────────────►┼────── relay ───────►│        │
│                                                             │
│  Both connected TO relay = both holes point inward          │
│  Relay just forwards encrypted blobs                        │
│  Cannot read message content (onion encryption)             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Mobile-Specific Considerations

### Network Switching

```
Phone switches WiFi → 4G:
  • IP address changes
  • Old holes become invalid
  • Must re-discover via STUN
  • Must re-punch holes

Solution:
  • Detect network change events
  • Re-run STUN discovery
  • Re-establish connections
  • Notify peers of new address
```

### Battery Optimization

```
Aggressive keep-alive drains battery.

Solution:
  • Longer keep-alive interval when idle (60s)
  • Shorter interval during active chat (15s)
  • Use store-and-forward for truly idle periods
  • Wake on incoming via relay ping
```

### Carrier-Grade NAT (CGNAT)

Some mobile carriers use double NAT:

```
Phone → Carrier NAT → Internet NAT → Internet

Both NATs need holes punched.
Usually still works with standard hole punching.
May need relay more often.
```

---

## Code Structure

```
src/transport/
  udp.c              UDP socket management
  stun.c             STUN protocol implementation
  hole_punch.c       Hole punching logic
  relay.c            Relay client/server

include/cyxwiz/
  nat.h              NAT traversal API

Key functions:
  cyxwiz_stun_discover()     Get public address
  cyxwiz_hole_punch()        Establish P2P connection
  cyxwiz_relay_connect()     Fallback to relay
  cyxwiz_nat_keepalive()     Maintain connection
```

---

## Bootstrap Server Protocol

The bootstrap server helps peers discover each other. It's combined with relay in `cyxchat-server.c`.

### Message Types (0xF0-0xF3)

| Code | Message | Direction | Purpose |
|------|---------|-----------|---------|
| 0xF0 | REGISTER | Client→Server | "I'm online" |
| 0xF1 | REGISTER_ACK | Server→Client | "Got it" |
| 0xF2 | PEER_LIST | Server→Client | "Here's who's online" |
| 0xF3 | CONNECT_REQ | Both ways | "Peer X wants to connect" |

### Message Formats

**REGISTER (0xF0)**
```
┌──────────┬──────────────┬────────────┐
│ type (1) │ node_id (32) │ port (2)   │
└──────────┴──────────────┴────────────┘
Total: 35 bytes
```

**REGISTER_ACK (0xF1)**
```
┌──────────┐
│ type (1) │
└──────────┘
Total: 1 byte
```

**PEER_LIST (0xF2)**
```
┌──────────┬─────────────┬─────────────────────────────────┐
│ type (1) │ count (1)   │ peers[] (38 bytes each)         │
└──────────┴─────────────┴─────────────────────────────────┘
                         │
                         ▼ (repeated for each peer)
              ┌──────────────┬──────────┬────────────┐
              │ node_id (32) │ ip (4)   │ port (2)   │
              └──────────────┴──────────┴────────────┘
Max peers per list: 10
```

**CONNECT_REQ (0xF3)**
```
┌──────────┬───────────────────┬─────────────────┬─────────────────┐
│ type (1) │ requester_id (32) │ requester_ip (4)│ requester_port (2)│
└──────────┴───────────────────┴─────────────────┴─────────────────┘
Total: 39 bytes
```

### Bootstrap Flow

```
Peer A                    Bootstrap Server                    Peer B
   │                            │                               │
   │── REGISTER (A's ID) ──────►│                               │
   │◄── REGISTER_ACK ───────────│                               │
   │◄── PEER_LIST (B, C, ...) ──│                               │
   │                            │                               │
   │   (A wants to talk to B)   │                               │
   │                            │                               │
   │── CONNECT_REQ (to B) ─────►│                               │
   │                            │── CONNECT_REQ (from A) ──────►│
   │                            │   (includes A's IP:port)      │
   │                            │                               │
   │◄─────────── UDP Hole Punch (both sides send) ─────────────►│
```

---

## Relay Protocol Details

When hole punching fails, traffic goes through the relay server.

### Message Types (0xE0-0xE5)

| Code | Message | Direction | Purpose |
|------|---------|-----------|---------|
| 0xE0 | RELAY_CONNECT | Client→Server | "I want to relay to peer X" |
| 0xE1 | RELAY_CONNECT_ACK | Server→Client | "Relay established" |
| 0xE2 | RELAY_DISCONNECT | Client→Server | "Done relaying" |
| 0xE3 | RELAY_DATA | Both ways | "Forward this data" |
| 0xE4 | RELAY_KEEPALIVE | Client→Server | "I'm still here" |
| 0xE5 | RELAY_ERROR | Server→Client | "Something went wrong" |

### Message Formats

**RELAY_CONNECT (0xE0)**
```
┌──────────┬──────────────┬────────────┐
│ type (1) │ from_id (32) │ to_id (32) │
└──────────┴──────────────┴────────────┘
Total: 65 bytes
```

**RELAY_DATA (0xE3)**
```
┌──────────┬──────────────┬────────────┬──────────────┬─────────────┐
│ type (1) │ from_id (32) │ to_id (32) │ data_len (2) │ payload (N) │
└──────────┴──────────────┴────────────┴──────────────┴─────────────┘
Header: 67 bytes
Max payload: 1400 bytes
```

### Relay Flow

```
Peer A                      Relay Server                      Peer B
   │                             │                               │
   │  (hole punch failed)        │                               │
   │                             │                               │
   │── RELAY_CONNECT ───────────►│                               │
   │   (from=A, to=B)            │── RELAY_CONNECT ─────────────►│
   │                             │   (from=A, to=B)              │
   │◄── RELAY_CONNECT_ACK ───────│◄── RELAY_CONNECT_ACK ─────────│
   │                             │                               │
   │── RELAY_DATA ──────────────►│                               │
   │   (to=B, encrypted msg)     │── RELAY_DATA ────────────────►│
   │                             │   (from=A, encrypted msg)     │
   │                             │                               │
   │                             │◄── RELAY_DATA ────────────────│
   │◄── RELAY_DATA ──────────────│   (to=A, encrypted reply)     │
   │   (from=B, encrypted reply) │                               │
```

### What the Relay Server Sees

| Data | Visible to Server? |
|------|--------------------|
| Who is talking to whom | **Yes** (from_id, to_id in header) |
| When messages are sent | **Yes** (server processes them) |
| Message size | **Yes** (data_len field) |
| Message content | **No** (E2E encrypted payload) |
| Public keys | **No** (only node IDs) |

---

## Known Limitations

### IP Change During Active Session

**Current behavior:**
```
1. User on WiFi (IP: 1.2.3.4)
2. UDP hole punch established with peer
3. User moves to mobile data (IP: 5.6.7.8)
4. Old hole punch breaks (wrong IP)
5. Peer timeout after 30 seconds
6. Connection marked as disconnected
7. User must manually reconnect
```

**What should happen:**
```
1. Periodic STUN refresh (every 30-60s)
2. Detect IP change
3. Re-register with bootstrap server
4. Use relay as bridge during transition
5. Re-punch hole with new IP
6. Seamlessly restore direct connection
7. No message loss, no manual intervention
```

**Status:** Not yet implemented. See `TODO.md` for implementation plan.

### Symmetric NAT on Both Sides

When both peers have symmetric NAT, hole punching almost always fails.
Relay is required. This adds:
- ~50-100ms latency (extra hop)
- Server sees metadata (who talks to whom)
- Dependency on relay server availability

---

## References

- RFC 5389: STUN Protocol
- RFC 5245: ICE (Interactive Connectivity Establishment)
- RFC 6886: NAT-PMP (NAT Port Mapping Protocol)
