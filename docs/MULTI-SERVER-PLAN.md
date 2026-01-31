# Multi-Server Redundancy Plan
 Purpose of Verification Challenges

  The challenge protocol proves the server is who it claims to be — not an impersonator. Without it, anyone could spin up a fake server at the same IP (e.g., after a DNS hijack or IP takeover) and intercept all peer registrations.

  Flow:
  1. Client sends random 32-byte nonce to server
  2. Server signs the nonce with its Ed25519 private key
  3. Client verifies the signature against the hardcoded public key
  4. If valid → this is the real server, not an impersonator

  This prevents MITM attacks on the bootstrap infrastructure.

  Why the Server Ignores It

  There are two server binaries in tools/:

  | File                   | Handles Challenges?                                      | Notes                                 |
  |------------------------|----------------------------------------------------------|---------------------------------------|
  | tools/bootstrap.c      | No — only handles 0xF0 (register) and 0xF3 (connect_req) | The original basic server             |
  | tools/cyxchat-server.c | Yes — full support for 0xF5/0xF6/0xF9/0xFA               | Enhanced server with Ed25519 identity |

  The question is which one is deployed on 129.151.146.219:7777. If it's the basic bootstrap.c, it receives the 0xF9 challenge packet, hits the default: case in its switch, and silently drops it. The client never gets a response, times out after 10s, and retries forever.

  Do you know which server binary is running on the VPS? That determines whether this is a deployment issue (wrong binary) or a code issue.
## Summary
Add verified multi-server support with health-based failover for bootstrap/relay servers. Anyone verified by the project can run a server. Clients discover servers via seed list + DHT, ping them for health, and auto-select the best.

## Implementation Phases

### Phase 1: Server Registry (C library - new module)
**New files**: `lib/include/cyxchat/server_registry.h`, `lib/src/server_registry.c`

- `cyxchat_server_registry_t` manages up to 8 servers with states: UNKNOWN → VERIFYING → VERIFIED → HEALTHY/UNHEALTHY/REJECTED
- **Verification**: Ed25519 challenge-response. Client sends 32-byte nonce, server signs it, client verifies against known pubkey
- **Health check**: Every 15s send HEALTH_PING (9 bytes), expect HEALTH_PONG. 3 missed = unhealthy
- **Best server selection**: Sort healthy+verified servers by EMA latency (alpha=0.3)
- **Seed list**: Hardcoded array of `{addr, pubkey}` pairs (initially just current server)
- New message types: 0xF5 (HEALTH_PING), 0xF6 (HEALTH_PONG), 0xF9 (CHALLENGE), 0xFA (CHALLENGE_RESP)

### Phase 2: Server-Side Changes
**File**: `tools/cyxchat-server.c`

- Generate Ed25519 keypair on first run, save to `server_key.dat`, print pubkey for hardcoding
- Handle HEALTH_PING → reply HEALTH_PONG (echo timestamp)
- Handle CHALLENGE → sign nonce with Ed25519 key, reply CHALLENGE_RESP
- Add libsodium dependency to server build

### Phase 3: Connection Layer Integration
**File**: `lib/src/connection.c`, `lib/include/cyxchat/connection.h`

- Add `server_registry` field to `cyxchat_conn_ctx`
- In `conn_create()`: create registry, load seeds, add user-provided server, pick best bootstrap
- In `conn_poll()`: poll registry; if current bootstrap unhealthy, re-register with best available
- New APIs: `cyxchat_conn_get_server_registry()`, `cyxchat_conn_add_server()`

### Phase 4: Relay Failover
**File**: `lib/src/relay.c`

- Replace hardcoded `server_index = 0` with health-based selection (lowest latency among healthy servers)
- On send failure, try next-best server
- Sync latency data from registry into relay server entries

### Phase 5: DHT Server Discovery
**File**: `lib/src/connection.c`

- Every 10 min, DHT lookup for well-known key `SHA256("cyxchat-servers-v1")`
- Discovered servers added to registry (verified before use)
- Servers self-announce via `cyxwiz_dht_store()`

### Phase 6: FFI Bindings
**File**: `app/lib/ffi/bindings.dart`

- `cyxchat_conn_get_server_registry()` - get registry pointer
- `cyxchat_server_registry_get_all()` - get server list with states/latencies
- `cyxchat_conn_add_server()` - add server from UI

### Phase 7: Flutter UI
**Files**: `app/lib/providers/settings_provider.dart`, `app/lib/screens/settings_screen.dart`

- Migrate single bootstrap server to `List<String>` (backwards-compatible)
- New `server_status_provider.dart` - polls C library every 5s for server health
- Settings screen: server list with health indicators, latency badges, add/remove buttons

## Critical Files
- `lib/include/cyxchat/server_registry.h` (new)
- `lib/src/server_registry.c` (new)
- `lib/src/relay.c` (fix hardcoded server selection)
- `lib/src/connection.c` (integrate registry)
- `tools/cyxchat-server.c` (add identity + health)
- `app/lib/ffi/bindings.dart` (new FFI bindings)
- `app/lib/providers/settings_provider.dart` (multi-server settings)
- `app/lib/screens/settings_screen.dart` (server list UI)
- `lib/CMakeLists.txt` (add new source file)
