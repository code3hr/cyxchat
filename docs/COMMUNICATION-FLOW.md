# CyxChat Communication Flow

Complete end-to-end documentation of how messages flow through the CyxChat system.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUTTER APP (Dart)                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ ChatScreen  │  │ Providers   │  │ Services                │  │
│  │ (UI)        │→ │ (State)     │→ │ (Identity, Chat, DB)    │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    FFI BINDINGS (bindings.dart)                 │
│              Dart ↔ C bridge via dart:ffi                       │
├─────────────────────────────────────────────────────────────────┤
│                    LIBCYXCHAT (C Library)                       │
│  ┌─────────┐  ┌────────────┐  ┌───────┐  ┌─────┐  ┌──────────┐ │
│  │ chat.c  │  │connection.c│  │relay.c│  │dns.c│  │presence.c│ │
│  └─────────┘  └────────────┘  └───────┘  └─────┘  └──────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    LIBCYXWIZ (Core Protocol)                    │
│  ┌───────────┐  ┌─────────┐  ┌───────┐  ┌─────┐  ┌───────────┐ │
│  │ transport │  │ routing │  │ onion │  │ dht │  │ discovery │ │
│  │ (UDP/NAT) │  │ (mesh)  │  │ (E2E) │  │     │  │           │ │
│  └───────────┘  └─────────┘  └───────┘  └─────┘  └───────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Message Sending Flow

### Step-by-Step: User Sends "Hello"

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. USER INPUT                                                    │
├──────────────────────────────────────────────────────────────────┤
│ User types "Hello" in ChatScreen and taps Send button            │
│                                                                  │
│ ChatScreen._sendMessage()                                        │
│   └─> chatActionsProvider.sendMessage(conversationId, "Hello")   │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 2. FLUTTER PROVIDER                                              │
├──────────────────────────────────────────────────────────────────┤
│ ChatProvider.sendText(peerId, text)                              │
│   ├─ Convert peer ID hex string to bytes                         │
│   ├─ Allocate native memory for peer ID                          │
│   └─> _bindings.chatSendText(peerIdPtr, "Hello", null)           │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 3. FFI BRIDGE                                                    │
├──────────────────────────────────────────────────────────────────┤
│ CyxChatBindings.chatSendText()                                   │
│   ├─ Convert Dart String to native UTF8                          │
│   ├─ Allocate output buffer for message ID                       │
│   └─> _native.cyxchat_send_text(ctx, to, text, len, reply, out)  │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 4. LIBCYXCHAT (chat.c)                                           │
├──────────────────────────────────────────────────────────────────┤
│ cyxchat_send_text()                                              │
│   ├─ Generate random 8-byte message ID                           │
│   ├─ Set flags: ENCRYPTED (+ REPLY if replying)                  │
│   ├─ Serialize to wire format:                                   │
│   │   [type:1][flags:1][msg_id:8][text_len:1][text:N]            │
│   │   Total: 11 + N bytes (compact wire format)                  │
│   └─> cyxwiz_onion_send_to(onion, peer_id, buffer, length)       │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 5. ONION ROUTING (cyxwiz/onion.c)                                │
├──────────────────────────────────────────────────────────────────┤
│ cyxwiz_onion_send_to()                                           │
│   ├─ Look up peer's X25519 public key                            │
│   ├─ Compute shared secret via DH key exchange                   │
│   ├─ Encrypt with XChaCha20-Poly1305:                            │
│   │   [nonce:24][ciphertext:N][auth_tag:16]                      │
│   │   Overhead: 40 bytes per hop                                 │
│   └─> cyxwiz_router_send(router, peer_id, encrypted, length)     │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 6. MESH ROUTING (cyxwiz/routing.c)                               │
├──────────────────────────────────────────────────────────────────┤
│ cyxwiz_router_send()                                             │
│   ├─ Check if peer is direct neighbor → send directly            │
│   ├─ Check route cache (expires after 60s)                       │
│   ├─ If no route: broadcast ROUTE_REQ, wait for ROUTE_REPLY      │
│   ├─ Use source routing: embed full path in packet header        │
│   │   [type:1][hop_count:1][hops:N*32][payload]                  │
│   └─> transport->ops->send(transport, next_hop, packet, len)     │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 7. TRANSPORT (cyxwiz/transport.c + udp.c)                        │
├──────────────────────────────────────────────────────────────────┤
│ UDP Transport send()                                             │
│   ├─ Look up peer's endpoint (IP:port from peer table)           │
│   ├─ sendto(socket, data, len, 0, peer_addr, addr_len)           │
│   └─> Packet sent over network                                   │
│                                                                  │
│ Note: CyxChat currently uses UDP transport only.                 │
│   Relay fallback via bootstrap server when direct fails.         │
└──────────────────────────────────────────────────────────────────┘
                               ↓
                        [ NETWORK ]
                               ↓
                           PEER
```

## Message Receiving Flow

### Step-by-Step: Peer Receives "Hello"

```
                           PEER
                               ↓
                        [ NETWORK ]
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 1. TRANSPORT RECEIVE                                             │
├──────────────────────────────────────────────────────────────────┤
│ UDP socket receives packet                                       │
│   └─> on_transport_recv(transport, from, data, len, user_data)   │
│       Callback registered during transport init                  │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 2. CONNECTION LAYER (connection.c)                               │
├──────────────────────────────────────────────────────────────────┤
│ on_transport_recv()                                              │
│   ├─ Check message type byte                                     │
│   ├─ Route to appropriate handler:                               │
│   │   ├─ 0xE0-0xE5: Relay protocol → cyxchat_relay_handle()      │
│   │   ├─ 0xF0-0xF3: Bootstrap protocol → handled internally      │
│   │   └─ Other: Forward to router/onion layer                    │
│   └─> cyxwiz_router_handle() or cyxwiz_onion_handle()            │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 3. ONION DECRYPTION (cyxwiz/onion.c)                             │
├──────────────────────────────────────────────────────────────────┤
│ cyxwiz_onion_unwrap()                                            │
│   ├─ Extract nonce (24 bytes)                                    │
│   ├─ Decrypt with XChaCha20-Poly1305 using shared secret         │
│   ├─ Verify Poly1305 auth tag (16 bytes)                         │
│   ├─ If verification fails → drop packet (tampered)              │
│   └─> on_onion_delivery(ctx, from, plaintext, len, user_data)    │
│       Callback delivers decrypted payload to app layer           │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 4. CHAT MESSAGE HANDLING (chat.c)                                │
├──────────────────────────────────────────────────────────────────┤
│ on_onion_delivery()                                              │
│   ├─ Parse wire format header:                                   │
│   │   type = data[0]  (0x10 = TEXT)                              │
│   │   flags = data[1]                                            │
│   │   msg_id = data[2..9]                                        │
│   ├─ Parse payload based on type:                                │
│   │   TEXT: text_len(1) + text(N) + reply_to?(8)                 │
│   │   ACK: ack_id(8) + status(1)                                 │
│   │   TYPING: is_typing(1)                                       │
│   │   REACTION: target_id(8) + emoji_len(1) + emoji + remove(1)  │
│   ├─ Queue in ring buffer:                                       │
│   │   recv_queue[head] = {from, type, data, valid=1}             │
│   │   head = (head + 1) % QUEUE_SIZE                             │
│   └─> Return (message ready for FFI polling)                     │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 5. FFI POLLING (bindings.dart + chat.c)                          │
├──────────────────────────────────────────────────────────────────┤
│ Flutter Timer.periodic(50ms) → ChatProvider._poll()              │
│   ├─ _bindings.chatPoll(now_ms)                                  │
│   │   └─> cyxchat_poll() - process timeouts, returns queue count │
│   └─ Loop while messages available:                              │
│       ├─ _bindings.chatRecvNext()                                │
│       │   └─> cyxchat_recv_next() - pop from ring buffer         │
│       │       Returns: from_id, type, data bytes                 │
│       └─> _processReceivedMessage(from, type, data)              │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 6. DART STREAM EMISSION                                          │
├──────────────────────────────────────────────────────────────────┤
│ ChatProvider._processReceivedMessage()                           │
│   ├─ Parse message based on type:                                │
│   │   TEXT → TextMessageData(text, replyToMsgId)                 │
│   │   ACK → AckData(msgId, status)                               │
│   │   TYPING → TypingStatus(peerId, isTyping)                    │
│   │   REACTION → ReactionData(targetId, emoji, remove)           │
│   ├─ Create ReceivedMessage object                               │
│   └─> _messageController.add(receivedMessage)                    │
│       Emits to messageStream                                     │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ 7. UI UPDATE                                                     │
├──────────────────────────────────────────────────────────────────┤
│ ConversationProvider listens to ChatProvider.messageStream       │
│   ├─ Receives ReceivedMessage event                              │
│   ├─ Updates internal message list state                         │
│   └─> notifyListeners()                                          │
│                                                                  │
│ ChatScreen watches ConversationProvider                          │
│   ├─ ListView.builder rebuilds                                   │
│   ├─ New message bubble appears                                  │
│   └─ Auto-scroll to bottom                                       │
└──────────────────────────────────────────────────────────────────┘
```

## Connection Establishment

### Phase 1: Initialization

```
┌──────────────────────────────────────────────────────────────────┐
│ APP STARTUP                                                      │
├──────────────────────────────────────────────────────────────────┤
│ main.dart → IdentityService.initialize()                         │
│   ├─ Load or generate 32-byte node ID                            │
│   └─ Store in flutter_secure_storage                             │
│                                                                  │
│ ConnectionActions.connect()                                      │
│   └─> ConnectionProvider.initialize(bootstrap, localId)          │
│       └─> FFI: cyxchat_conn_create(bootstrap, local_id)          │
└──────────────────────────────────────────────────────────────────┘
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│ C LAYER INITIALIZATION (connection.c)                            │
├──────────────────────────────────────────────────────────────────┤
│ cyxchat_conn_create()                                            │
│   ├─ Set CYXWIZ_BOOTSTRAP environment variable                   │
│   ├─ Create transport: cyxwiz_transport_create(UDP)              │
│   ├─ Create peer table: cyxwiz_peer_table_create()               │
│   ├─ Create router: cyxwiz_router_create()                       │
│   ├─ Create onion: cyxwiz_onion_create() [X25519 keypair]        │
│   ├─ Create DHT: cyxwiz_dht_create()                             │
│   ├─ Create relay: cyxchat_relay_create()                        │
│   ├─ Set callbacks:                                              │
│   │   ├─ on_transport_recv → receive handler                     │
│   │   ├─ on_peer_discovered → peer table update                  │
│   │   └─ on_relay_data → relay fallback handler                  │
│   └─> transport->ops->discover() - start peer discovery          │
└──────────────────────────────────────────────────────────────────┘
```

### Phase 2: STUN Discovery

```
┌──────────────────────────────────────────────────────────────────┐
│ STUN (Session Traversal Utilities for NAT)                       │
├──────────────────────────────────────────────────────────────────┤
│ UDP transport init (udp.c)                                       │
│   ├─ Bind to random local port                                   │
│   ├─ Send STUN binding request to:                               │
│   │   ├─ stun.l.google.com:19302                                 │
│   │   └─ stun.cloudflare.com:3478                                │
│   ├─ Receive STUN response with:                                 │
│   │   ├─ XOR-MAPPED-ADDRESS (public IP:port)                     │
│   │   └─ MAPPED-ADDRESS (backup)                                 │
│   ├─ Detect NAT type:                                            │
│   │   ├─ OPEN: No NAT, direct reachable                          │
│   │   ├─ FULL_CONE: Any external can reach mapped port           │
│   │   ├─ RESTRICTED: Only replied-to hosts can reach             │
│   │   ├─ PORT_RESTRICTED: Only replied-to host:port can reach    │
│   │   ├─ SYMMETRIC: Different mapping per destination            │
│   │   └─ BLOCKED: No external connectivity                       │
│   └─> Store public endpoint for bootstrap registration           │
│                                                                  │
│ Refresh: Every 60 seconds (NAT mappings expire)                  │
└──────────────────────────────────────────────────────────────────┘
```

### Phase 3: Bootstrap Registration

```
┌──────────────────────────────────────────────────────────────────┐
│ BOOTSTRAP SERVER REGISTRATION                                    │
├──────────────────────────────────────────────────────────────────┤
│ bootstrap_register() in udp.c                                    │
│   ├─ Build register message:                                     │
│   │   [type:0xF0][node_id:32][local_port:2]                      │
│   ├─ Send to bootstrap server (from CYXWIZ_BOOTSTRAP env)        │
│   └─> Receive:                                                   │
│       ├─ REGISTER_ACK (0xF1): Registration confirmed             │
│       └─ PEER_LIST (0xF2): List of other registered peers        │
│           [type:0xF2][count:1][peer_entries:N*38]                │
│           Each entry: [node_id:32][ip:4][port:2]                 │
│                                                                  │
│ Re-register: Every 60 seconds (peers expire after 120s)          │
└──────────────────────────────────────────────────────────────────┘
```

### Phase 4: Peer Connection

```
┌──────────────────────────────────────────────────────────────────┐
│ CONNECTING TO A PEER                                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ State Machine: DISCONNECTED → DISCOVERING → CONNECTING →         │
│                CONNECTED (or RELAYING if hole punch fails)       │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│ STEP 1: DISCOVERING                                              │
│   ├─ If peer in peer table: skip to CONNECTING                   │
│   └─ DHT lookup: cyxwiz_dht_find_node(dht, peer_id)              │
│       ├─ Send FIND_NODE to K closest known peers                 │
│       ├─ Peers respond with their closest peers                  │
│       ├─ Iterate until target found or no closer peers           │
│       └─> Timeout: 5 seconds                                     │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│ STEP 2: CONNECTING (UDP Hole Punch)                              │
│   ├─ Get peer's public endpoint from peer table                  │
│   ├─ Send hole punch packets:                                    │
│   │   ├─ 5 attempts, 50ms apart                                  │
│   │   └─ [type:0xF4][node_id:32] to peer's public IP:port        │
│   ├─ Simultaneously, peer sends packets to our public IP:port    │
│   ├─ NAT creates mapping when outbound packet sent               │
│   ├─ Peer's packet arrives through our NAT mapping               │
│   └─> If packet received within 5s: SUCCESS                      │
│       └─> State = CONNECTED, is_relayed = 0                      │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│ STEP 3: RELAYING (Fallback)                                      │
│   ├─ If hole punch times out (symmetric NAT, firewall)           │
│   ├─ Check CYXCHAT_RELAY environment variable                    │
│   ├─ Send via relay server:                                      │
│   │   [type:0xE0][from_id:32][to_id:32] - RELAY_CONNECT          │
│   │   [type:0xE3][from_id:32][to_id:32][len:2][data:N] - DATA    │
│   ├─ Relay forwards to peer                                      │
│   └─> State = CONNECTED, is_relayed = 1                          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Wire Formats

### Chat Message Types (0x10-0x1F)

```
TEXT (0x10):
┌──────┬───────┬─────────┬──────────┬──────────┬───────────┐
│ type │ flags │ msg_id  │ text_len │ text     │ reply_to? │
│ 1B   │ 1B    │ 8B      │ 1B       │ N bytes  │ 8B        │
└──────┴───────┴─────────┴──────────┴──────────┴───────────┘
Flags: 0x01=ENCRYPTED, 0x02=REPLY

ACK (0x11):
┌──────┬───────┬─────────┬────────┬────────┐
│ type │ flags │ msg_id  │ ack_id │ status │
│ 1B   │ 1B    │ 8B      │ 8B     │ 1B     │
└──────┴───────┴─────────┴────────┴────────┘
Status: 0=SENT, 1=DELIVERED, 2=READ

TYPING (0x12):
┌──────┬───────┬─────────┬───────────┐
│ type │ flags │ msg_id  │ is_typing │
│ 1B   │ 1B    │ 8B      │ 1B        │
└──────┴───────┴─────────┴───────────┘

READ_RECEIPT (0x13):
┌──────┬───────┬─────────┬────────────┐
│ type │ flags │ msg_id  │ receipt_id │
│ 1B   │ 1B    │ 8B      │ 8B         │
└──────┴───────┴─────────┴────────────┘

REACTION (0x14):
┌──────┬───────┬─────────┬───────────┬───────────┬───────┬────────┐
│ type │ flags │ msg_id  │ target_id │ emoji_len │ emoji │ remove │
│ 1B   │ 1B    │ 8B      │ 8B        │ 1B        │ N     │ 1B     │
└──────┴───────┴─────────┴───────────┴───────────┴───────┴────────┘

DELETE (0x15):
┌──────┬───────┬─────────┬───────────┐
│ type │ flags │ msg_id  │ target_id │
│ 1B   │ 1B    │ 8B      │ 8B        │
└──────┴───────┴─────────┴───────────┘

EDIT (0x16):
┌──────┬───────┬─────────┬───────────┬──────────┬──────────┐
│ type │ flags │ msg_id  │ target_id │ text_len │ new_text │
│ 1B   │ 1B    │ 8B      │ 8B        │ 1B       │ N bytes  │
└──────┴───────┴─────────┴───────────┴──────────┴──────────┘
```

### Protocol Message Types

```
Bootstrap (0xF0-0xF3):
  0xF0 REGISTER      - Register with bootstrap server
  0xF1 REGISTER_ACK  - Registration acknowledged
  0xF2 PEER_LIST     - List of known peers
  0xF3 CONNECT_REQ   - Connection request relay

Relay (0xE0-0xE5):
  0xE0 RELAY_CONNECT     - Connect via relay
  0xE1 RELAY_CONNECT_ACK - Connection acknowledged
  0xE2 RELAY_DISCONNECT  - Disconnect
  0xE3 RELAY_DATA        - Relayed data
  0xE4 RELAY_KEEPALIVE   - Keepalive
  0xE5 RELAY_ERROR       - Error response

Routing (0x20-0x24):
  0x20 ROUTE_REQ    - Route request (broadcast)
  0x21 ROUTE_REPLY  - Route reply (unicast)
  0x22 ROUTE_DATA   - Routed data packet
  0x23 ROUTE_ERROR  - Route error
  0x24 ONION_DATA   - Onion-encrypted data

Discovery (0x01-0x05):
  0x01 ANNOUNCE     - Peer announcement
  0x02 ANNOUNCE_ACK - Announcement response
  0x03 PING         - Keepalive ping
  0x04 PONG         - Keepalive response
  0x05 GOODBYE      - Graceful disconnect
```

### File Transfer Message Types (0x14-0x16, 0x40-0x45, 0x60-0x61)

**Important:** File messages include `sender_id` in the wire format to support onion routing.
When messages are relayed via onion routing, the transport-layer `from` address is the
relay node, not the original sender. File messages embed the sender's node ID directly
in the payload so receivers can identify the true sender.

```
FILE_META (0x14) - File metadata/offer:
┌──────┬───────────┬─────────┬───────────┬──────────┬──────────┬──────┬─────────────┬───────────┐
│ type │ sender_id │ file_id │ fname_len │ filename │ mime_len │ mime │ size (LE32) │ chunks    │
│ 1B   │ 32B       │ 8B      │ 1B        │ N bytes  │ 1B       │ N    │ 4B          │ 2B + 32B  │
└──────┴───────────┴─────────┴───────────┴──────────┴──────────┴──────┴─────────────┴───────────┘
Note: chunks = chunk_count(2B) + file_hash(32B)

FILE_CHUNK (0x15) - File data chunk:
┌──────┬───────────┬─────────┬───────────┬───────────┬────────────┐
│ type │ sender_id │ file_id │ chunk_idx │ chunk_len │ chunk_data │
│ 1B   │ 32B       │ 8B      │ 2B (LE)   │ 2B (LE)   │ N bytes    │
└──────┴───────────┴─────────┴───────────┴───────────┴────────────┘

FILE_ACK (0x16) - Chunk acknowledgment:
┌──────┬───────────┬─────────┬───────────┐
│ type │ sender_id │ file_id │ chunk_idx │
│ 1B   │ 32B       │ 8B      │ 2B        │
└──────┴───────────┴─────────┴───────────┘

FILE_ACCEPT (0x41) - Accept file transfer:
┌──────┬───────────┬─────────┬──────┬─────────────┐
│ type │ sender_id │ file_id │ mode │ start_chunk │
│ 1B   │ 32B       │ 8B      │ 1B   │ 2B          │
└──────┴───────────┴─────────┴──────┴─────────────┘

FILE_REJECT (0x42) - Reject file transfer:
┌──────┬───────────┬─────────┬────────┐
│ type │ sender_id │ file_id │ reason │
│ 1B   │ 32B       │ 8B      │ 1B     │
└──────┴───────────┴─────────┴────────┘

FILE_CANCEL (0x44) - Cancel transfer:
┌──────┬───────────┬─────────┐
│ type │ sender_id │ file_id │
│ 1B   │ 32B       │ 8B      │
└──────┴───────────┴─────────┘

PEER_ADDR (0x60) - Peer address for direct P2P:
┌──────┬───────────┬─────────┬───────────┬─────────────┐
│ type │ sender_id │ file_id │ public_ip │ public_port │
│ 1B   │ 32B       │ 8B      │ 4B        │ 2B          │
└──────┴───────────┴─────────┴───────────┴─────────────┘

PEER_ADDR_ACK (0x61) - Peer address acknowledgment:
┌──────┬───────────┬─────────┐
│ type │ sender_id │ file_id │
│ 1B   │ 32B       │ 8B      │
└──────┴───────────┴─────────┘
```

#### Why sender_id is Required in File Messages

Unlike text messages which use a wire header containing `sender_id`, file messages
originally used a simpler format without sender identification. This caused issues
with onion routing:

```
Problem (before fix):
  Alice ──onion──▶ Bob (relay) ──onion──▶ Carol

  Carol's on_delivery callback receives:
    from = Bob's ID (the relay node)  ❌ WRONG

Solution (after fix):
  File messages now embed sender_id in wire format:
    from = parsed from message payload = Alice's ID  ✓ CORRECT
```

## Encryption

### Onion Routing Encryption

```
┌──────────────────────────────────────────────────────────────────┐
│ KEY EXCHANGE (X25519)                                            │
├──────────────────────────────────────────────────────────────────┤
│ Each node generates X25519 keypair on init:                      │
│   ├─ Private key: 32 random bytes                                │
│   └─ Public key: crypto_scalarmult_base(private)                 │
│                                                                  │
│ Shared secret computed via DH:                                   │
│   shared = crypto_scalarmult(my_private, peer_public)            │
│   key = BLAKE2b(shared, "cyxwiz-onion-key")                      │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ MESSAGE ENCRYPTION (XChaCha20-Poly1305)                          │
├──────────────────────────────────────────────────────────────────┤
│ Encrypt:                                                         │
│   nonce = 24 random bytes                                        │
│   ciphertext = XChaCha20(plaintext, key, nonce)                  │
│   tag = Poly1305(ciphertext, key)                                │
│   output = nonce || ciphertext || tag                            │
│                                                                  │
│ Overhead per hop: 24 (nonce) + 16 (tag) = 40 bytes               │
│                                                                  │
│ Max payload (250 byte packet limit):                             │
│   1-hop: 250 - 40 = 210 bytes                                    │
│   2-hop: 250 - 80 = 170 bytes                                    │
│   3-hop: 250 - 120 = 130 bytes                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Timing Configuration

| Component | Interval | Purpose |
|-----------|----------|---------|
| Chat poll | 50ms | Check for received messages |
| Connection poll | 100ms | Update connection state |
| STUN refresh | 60s | Rediscover public IP |
| Bootstrap register | 60s | Re-register with server |
| Keepalive | 30s | Maintain NAT mapping |
| Route cache TTL | 60s | Expire stale routes |
| Circuit TTL | 60s | Expire onion circuits |
| Peer timeout | 90s | Remove inactive peers |
| Hole punch timeout | 5s | Fall back to relay |
| DHT lookup timeout | 5s | Give up on peer search |

## Error Handling

| Error Code | Value | Meaning | Recovery |
|------------|-------|---------|----------|
| OK | 0 | Success | - |
| ERR_NULL | -1 | Null pointer | Check inputs |
| ERR_MEMORY | -2 | Allocation failed | Retry later |
| ERR_INVALID | -3 | Invalid parameter | Fix input |
| ERR_NOT_FOUND | -4 | Item not found | DHT lookup |
| ERR_EXISTS | -5 | Already exists | Skip |
| ERR_FULL | -6 | Container full | Wait/retry |
| ERR_CRYPTO | -7 | Crypto failed | Drop message |
| ERR_NETWORK | -8 | Network error | Use relay |
| ERR_TIMEOUT | -9 | Operation timeout | Retry/relay |
| ERR_BLOCKED | -10 | User blocked | Inform user |

## File Reference

### Flutter Layer
- `app/lib/main.dart` - App entry, theme
- `app/lib/screens/chat_screen.dart` - Chat UI
- `app/lib/providers/chat_provider.dart` - Message handling
- `app/lib/providers/connection_provider.dart` - Connection state
- `app/lib/ffi/bindings.dart` - FFI bridge

### C Library (libcyxchat)
- `lib/src/chat.c` - Message send/receive
- `lib/src/connection.c` - NAT traversal, relay
- `lib/src/relay.c` - Relay protocol
- `lib/src/dns.c` - Username resolution
- `lib/src/presence.c` - Online status

### Core Protocol (libcyxwiz)
- `../../src/transport/udp.c` - UDP + STUN
- `../../src/core/routing.c` - Mesh routing
- `../../src/core/onion.c` - E2E encryption
- `../../src/core/dht.c` - Peer discovery
- `../../src/core/discovery.c` - Peer announcements
