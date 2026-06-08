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
1. UPnP/NAT-PMP port mapping (at transport init)
   ├─ Works ~40% of home routers
   └─ If successful, skip hole punching entirely
   ↓ fail
2. Try direct hole punch (works ~80% of time)
   ↓ fail
3. Try port prediction (works ~30% for symmetric)
   ↓ fail
4. Use relay node (always works, still encrypted)

Total success: ~95%+
```

---

## UPnP/NAT-PMP Port Mapping

### What Is UPnP?

UPnP (Universal Plug and Play) IGD (Internet Gateway Device) allows applications
to automatically configure port forwarding on the router without manual setup.

NAT-PMP (NAT Port Mapping Protocol) is Apple's simpler alternative, commonly
found in Apple routers and some other vendors.

### How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│                     UPnP Port Mapping                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CyxChat App                              Router (IGD)           │
│       │                                       │                  │
│       │── SSDP Discovery ────────────────────►│                  │
│       │   (M-SEARCH for upnp:rootdevice)      │                  │
│       │                                       │                  │
│       │◄── SSDP Response ─────────────────────│                  │
│       │    (Location: http://192.168.1.1...)  │                  │
│       │                                       │                  │
│       │── AddPortMapping ────────────────────►│                  │
│       │   (internal:12345, external:12345,    │                  │
│       │    protocol:UDP, lease:3600s)         │                  │
│       │                                       │                  │
│       │◄── Success ───────────────────────────│                  │
│       │                                       │                  │
│       │   Result: External traffic to port    │                  │
│       │   12345 forwards to this device       │                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### CyxWiz UPnP API

```c
// Create UPnP state
cyxwiz_upnp_state_t *upnp;
cyxwiz_upnp_create(&upnp);

// Discover gateway (2 second timeout)
if (cyxwiz_upnp_discover(upnp) == CYXWIZ_OK) {
    // Gateway found! Add port mapping
    cyxwiz_upnp_add_mapping(upnp,
        12345,    // internal port
        0,        // external port (0 = same as internal)
        3600      // lease duration (1 hour)
    );
}

// Get status
cyxwiz_upnp_status_t status;
cyxwiz_upnp_get_status(upnp, &status);
printf("LAN: %s, WAN: %s, Port: %d\n",
    status.lan_addr, status.wan_addr, status.external_port);

// Cleanup (removes mapping)
cyxwiz_upnp_destroy(upnp);
```

### UPnP vs Hole Punching

| Feature | UPnP/NAT-PMP | UDP Hole Punch |
|---------|--------------|----------------|
| Router support | ~40% | ~80% |
| Setup time | 2-3 seconds | 100-500ms |
| Incoming connections | Immediate | Need simultaneous punch |
| Requires peer online | No | Yes |
| Works with symmetric NAT | Yes | No |
| Lease management | Required (hourly renewal) | NAT timeout (~60s) |

### When UPnP Fails

UPnP may fail due to:
- Router doesn't support UPnP/NAT-PMP
- UPnP disabled in router settings
- ISP-managed router with locked settings
- Double NAT (carrier-grade NAT)
- Firewall blocking SSDP

When UPnP fails, CyxWiz automatically falls back to hole punching, then relay.

### Security Considerations

UPnP port mappings are visible to the local network. The mapping:
- Only opens the specific port requested
- Is removed on app shutdown
- Has a 1-hour lease (auto-renewed while app runs)
- Does not expose any credentials

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

## Relay + Onion Routing Interaction

### Protocol Layer Stack

Onion routing operates **above** the transport layer. Relay fallback happens at the transport layer:

```
┌─────────────────────────────────────┐
│  Application (Chat messages)        │  ← Your message content
├─────────────────────────────────────┤
│  Onion Routing                      │  ← Layered encryption, hides destination
├─────────────────────────────────────┤
│  Mesh Router                        │  ← Multi-hop path selection
├─────────────────────────────────────┤
│  Transport (UDP)                    │  ← Relay fallback happens HERE
│    • Direct P2P (hole punch)        │
│    • OR Relay (when punch fails)    │
└─────────────────────────────────────┘
```

This means onion routing still works when using relay - the relay just becomes the transport mechanism.

### How It Works Together

**Direct P2P + Onion (best privacy):**
```
Alice ──encrypt layers──► Hop1 ──► Hop2 ──► Bob
                            │
                     Each hop only knows
                     previous + next hop
```

**Relay + Onion (when hole punch fails):**
```
Alice ──encrypt layers──► [Relay] ──► Hop1 ──► Hop2 ──► Bob
                             │
                      Relay sees encrypted
                      onion blob, not content
                      or final destination
```

**Relay + Direct (no onion, 1-hop):**
```
Alice ──encrypt──► [Relay] ──► Bob
                      │
               Relay sees both
               Alice and Bob IDs
               (from relay header)
```

### Privacy Comparison

| Scenario | Content | Final Destination | Metadata |
|----------|---------|-------------------|----------|
| **Direct P2P** | Hidden (E2E) | Exposed to first hop | Minimal (no intermediary) |
| **Direct P2P + Onion** | Hidden (E2E) | Hidden (onion) | Minimal |
| **Relay only** | Hidden (E2E) | **Exposed** (relay header) | Relay sees both parties |
| **Relay + Onion** | Hidden (E2E) | Hidden (onion) | Relay sees Alice + first hop only |

### Detailed Metadata Exposure

**Direct P2P (no relay):**
| What | Who Sees It |
|------|-------------|
| Your IP address | Direct peer only |
| Message timing | No central observer |
| Communication pattern | No central observer |
| Who you talk to | Direct peer only |

**Relay (without multi-hop onion):**
| What | Who Sees It |
|------|-------------|
| Your IP address | Relay server |
| Message timing | Relay server |
| Communication pattern | Relay server |
| Who you talk to | **Relay server** (from_id, to_id in header) |
| Message content | Nobody (E2E encrypted) |

**Relay + Multi-hop Onion:**
| What | Who Sees It |
|------|-------------|
| Your IP address | Relay server |
| Message timing | Relay server |
| That you're communicating | Relay server |
| **Who you're talking to** | **Hidden** (onion hides final destination) |
| Message content | Nobody (E2E encrypted) |

### When Is Each Mode Used?

```
Connection attempt flow:

1. Try UDP hole punch
   ├── Success → Direct P2P
   │             └── Onion optional (use /anon command)
   │
   └── Fail (symmetric NAT, firewall)
             │
             ▼
2. Fall back to relay
   └── Onion still works on top
       └── Use multi-hop for destination privacy
```

### Practical Implications

**For most users (relay fallback):**
- Message content is always protected (E2E encryption)
- Relay server knows you're talking to someone
- If using 1-hop direct to recipient: relay knows exactly who
- If using multi-hop onion: relay only knows first hop

**For maximum privacy:**
- Prefer direct P2P connections (hole punch success)
- Use multi-hop onion routing for sensitive conversations
- Be aware that relay server is a metadata observer
- Consider self-hosting relay for full control

### Summary

| Privacy Goal | Direct P2P | Relay | Relay + Onion |
|--------------|------------|-------|---------------|
| Hide message content | Yes | Yes | Yes |
| Hide who you talk to | No* | No | **Yes** |
| Hide that you're active | Yes | No | No |
| No central observer | Yes | No | No |

*Direct P2P: your peer knows, but no third party observes.

**Bottom line:** Relay + Onion provides "content privacy" but not "metadata privacy" for the fact you're communicating. It does hide your final destination from the relay when using multi-hop circuits.

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

---

## P2P vs Relay Asymmetry

### Why One Side Shows P2P and Other Shows Relay

A common confusion: "If I can reach you via P2P, why can't you reach me the same way?"

**Answer:** Each side tracks its own **outbound** path independently. NAT asymmetry can cause different outcomes for each direction.

### The Symmetric NAT Problem (Detailed)

```
┌─────────────────────────────────────────────────────────────────┐
│                     ASYMMETRIC CONNECTION                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Alice (Full Cone NAT)              Bob (Symmetric NAT)        │
│   ┌─────────┐                        ┌─────────┐                │
│   │ Phone   │                        │ Phone   │                │
│   │ 192.168.1.5                      │ 192.168.1.5              │
│   └────┬────┘                        └────┬────┘                │
│        │                                  │                     │
│   ┌────┴────┐                        ┌────┴────┐                │
│   │ Router  │                        │ Router  │                │
│   │ NAT     │                        │ NAT     │                │
│   └────┬────┘                        └────┬────┘                │
│        │                                  │                     │
│   Public: 1.1.1.1:5000               Public: 2.2.2.2:6000       │
│   (SAME for all destinations)        (ONLY for STUN server!)   │
│                                                                 │
│   Full Cone: "Anyone can send        Symmetric: "Different      │
│   to port 5000 once it's open"       port for each destination" │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Step 1: STUN Discovery
  • Alice asks STUN: "What's my address?" → 1.1.1.1:5000
  • Bob asks STUN: "What's my address?" → 2.2.2.2:6000

Step 2: Bootstrap Exchange
  • Bootstrap tells Alice: "Bob is at 2.2.2.2:6000"
  • Bootstrap tells Bob: "Alice is at 1.1.1.1:5000"

Step 3: The Problem
  • When Bob sends to Alice, Bob's NAT creates NEW port: 2.2.2.2:6001
  • The 6000 port was ONLY for talking to STUN server!

Step 4: Connection Attempts
  • Alice → 2.2.2.2:6000 → Bob's NAT: "No mapping for 6000 from Alice" → DROPPED ❌
  • Bob → 1.1.1.1:5000 → Alice's NAT: "Port 5000 is open to anyone" → DELIVERED ✓

Result:
  • Alice's view: "I can't reach Bob directly" → Relay
  • Bob's view: "I can reach Alice directly" → P2P
```

### Same PC / Same Network Testing

When testing with two instances on the **same PC** or **same network**:

```
┌─────────────────────────────────────────────────────────────────┐
│                     SAME PC / SAME NAT                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐    ┌──────────────┐                         │
│   │ Instance A   │    │ Instance B   │                         │
│   │ (Debug)      │    │ (Release)    │                         │
│   │ port 12345   │    │ port 12346   │                         │
│   └──────┬───────┘    └──────┬───────┘                         │
│          │                   │                                  │
│          └─────────┬─────────┘                                  │
│                    │                                            │
│            ┌───────┴───────┐                                    │
│            │  Your Router  │                                    │
│            │  (Same NAT)   │                                    │
│            └───────┬───────┘                                    │
│                    │                                            │
│            Public: 203.x.x.x                                    │
│                                                                 │
│   Both instances share:                                         │
│   • Same public IP                                              │
│   • Same NAT type                                               │
│   • Same router behavior                                        │
│                                                                 │
│   Expected: SYMMETRIC behavior (both P2P or both Relay)         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

If you see asymmetry on same PC, it's likely a TIMING issue:
  1. Instance A connects first
  2. Instance B not ready yet
  3. A's hole punch times out → falls back to Relay
  4. Instance B connects later
  5. B's hole punch succeeds (A is now "known")
  6. Result: A=Relay, B=P2P (timing artifact)

Solution: Ensure both instances are fully connected to bootstrap
          BEFORE initiating peer connections.
```

### Expected Behavior by Network Combination

| Your Network | Peer's Network | Expected Result |
|--------------|----------------|-----------------|
| Home Router | Home Router | Both P2P ✓ |
| Home Router | Mobile 4G/5G | Asymmetric (you=P2P, peer=Relay) |
| Mobile 4G/5G | Mobile 4G/5G | Both Relay (CGNAT on both) |
| Office/Corporate | Any | Usually Relay (strict firewall) |
| VPN | Any | Depends on VPN (usually Relay) |
| Same PC/Network | Same PC/Network | Both same (P2P or Relay) |

### Network Type Characteristics

| Network Type | NAT Type | Hole Punch Success |
|--------------|----------|-------------------|
| Home router (typical) | Full Cone / Restricted Cone | ✓ Usually works |
| Office network | Varies (often restricted) | ○ Sometimes works |
| Mobile 4G/5G | Symmetric / CGNAT | ✗ Usually fails |
| Hotel/Airport WiFi | Symmetric / Strict firewall | ✗ Usually fails |
| VPN | Depends on provider | ○ Varies |

### Visual Summary

```
┌─────────────────────────────────────────────────────────────────┐
│              CONNECTION OUTCOME MATRIX                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                         Peer B's NAT Type                       │
│                    Full Cone    Symmetric                       │
│                  ┌────────────┬────────────┐                    │
│  Peer A's   Full │   Both     │   A=P2P    │                    │
│  NAT Type   Cone │   P2P ✓    │   B=Relay  │                    │
│                  ├────────────┼────────────┤                    │
│           Symm.  │   A=Relay  │   Both     │                    │
│                  │   B=P2P    │   Relay    │                    │
│                  └────────────┴────────────┘                    │
│                                                                 │
│  Legend:                                                        │
│    P2P = Direct hole punch succeeded                            │
│    Relay = Hole punch failed, using relay server                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Important Notes

1. **Asymmetry is Normal**: Different NAT types cause legitimately different outcomes per direction
2. **Messages Still Work**: Both P2P and Relay deliver messages - just different paths
3. **Relay is Encrypted**: Relay server only forwards encrypted blobs, can't read content
4. **Each Side Independent**: Your `is_relayed` flag only tracks YOUR outbound path
5. **Timing Matters**: Same-network asymmetry usually means timing issue, not real NAT difference
