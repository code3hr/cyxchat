# CyxChat & CyxMail Documentation

Decentralized communication applications built on the CyxWiz protocol.

## Vision

**"WhatsApp + Gmail without servers"**

- No central servers - all peer-to-peer
- Works from any location (behind NAT, firewalls, mobile networks)
- End-to-end encrypted
- Local storage (your data stays on your device)
- Cross-platform (mobile + desktop)

---

## Documentation Index

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Overall system design and component overview |
| [NAT-TRAVERSAL.md](./NAT-TRAVERSAL.md) | UDP hole punching and relay fallback |
| [DNS.md](./DNS.md) | Human-readable usernames and service discovery |
| [LABELS.md](./LABELS.md) | MPLS-style efficient routing |
| [EMAIL.md](./EMAIL.md) | Decentralized email (CyxMail) |
| [GATEWAY.md](./GATEWAY.md) | Bridge to traditional email (Gmail, Outlook, etc.) |

---

## Key Technologies

### NAT Traversal
Most devices are behind NAT routers. We use:
- **STUN** to discover public addresses
- **UDP hole punching** for direct P2P connections
- **Relay nodes** as fallback when direct fails

### Internal DNS
Human-readable names instead of 32-byte node IDs:
- `alice.cyx` instead of `0x7a8b9c0d1e2f...`
- Decentralized (DHT-based)
- Includes connectivity info (STUN address, relays)

### MPLS-Style Labels
Efficient routing with short labels:
- 2-byte labels instead of 32-byte node IDs
- Enables 3-hop onion routing (was limited to 2)
- 88+ bytes more payload per message

### Store-and-Forward
Offline message delivery:
- Friend-based mailboxes
- DHT-based storage
- CyxCloud integration

---

## Applications

### CyxChat (Instant Messaging)
- Real-time chat when both online
- Offline delivery via mailbox
- File transfer (P2P, resumable)
- Group messaging
- Typing indicators, read receipts
- Multi-device sync

### CyxMail (Email)
- Async communication
- Large attachments (chunked)
- Threading (email conversations)
- IMAP4-style folders
- Full-text search
- **Gateway to Gmail/Outlook** (send to external email)

---

## Shared Infrastructure

Both applications share:

```
┌─────────────────────────────────────────┐
│           CyxChat / CyxMail             │
├─────────────────────────────────────────┤
│  • DNS (username resolution)            │
│  • NAT traversal (connectivity)         │
│  • Encryption (same keys)               │
│  • Mailbox (store-forward)              │
│  • Local storage (SQLite)               │
│  • Contact management                   │
└─────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────┐
│              CyxWiz Core                │
├─────────────────────────────────────────┤
│  • Transport (UDP, WiFi Direct, BT, LoRa│
│  • Routing (mesh, onion)                │
│  • Crypto (X25519, XChaCha20)           │
│  • Storage (CyxCloud)                   │
└─────────────────────────────────────────┘
```

---

## Implementation Status

### Phase 1: Core Connectivity ⏳
- [ ] UDP transport with STUN
- [ ] UDP hole punching
- [ ] Relay fallback
- [ ] Connection keep-alive

### Phase 2: Naming & Discovery ⏳
- [ ] Internal DNS (gossip-based)
- [ ] Username registration
- [ ] Presence tracking

### Phase 3: Chat Protocol ⏳
- [ ] Text messages
- [ ] Delivery receipts
- [ ] Store-and-forward
- [ ] Group messaging

### Phase 4: Email Protocol ⏳
- [ ] Message format
- [ ] Mailbox system
- [ ] Attachments
- [ ] Threading

### Phase 5: Email Gateway ⏳
- [ ] SMTP/IMAP integration
- [ ] Address mapping (alice.cyx ↔ alice@gateway.com)
- [ ] Inbound/outbound conversion
- [ ] Spam filtering

### Phase 6: Apps ⏳
- [ ] Mobile (iOS/Android)
- [ ] Desktop (Windows/Mac/Linux)
- [ ] Local encrypted storage
- [ ] Multi-device sync

---

## Design Decisions (Open)

| Decision | Options | Status |
|----------|---------|--------|
| Offline delivery | Friend relays / DHT / CyxCloud | TBD |
| Push notifications | None / Relay-triggered / Self-hosted | TBD |
| Identity model | Single key / Per-device / Hierarchical | TBD |
| Group architecture | Fan-out / Relay / Gossip | TBD |

---

## Related CyxWiz Docs

- [../CLAUDE.md](../CLAUDE.md) - Main protocol documentation
- [../cyxwiz-routing.md](../cyxwiz-routing.md) - Routing protocol
- [../cyxwiz-messaging.md](../cyxwiz-messaging.md) - Message formats
