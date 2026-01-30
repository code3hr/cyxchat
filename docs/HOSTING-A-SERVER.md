# Hosting a CyxChat Server

This guide explains how to set up and run your own CyxChat bootstrap/relay server and connect it to the network.

## Prerequisites

- Linux server (Ubuntu/Debian recommended) with a public IP
- UDP port 7777 open in firewall
- GCC compiler
- libsodium (for Ed25519 server identity)

## 1. Install Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y gcc libsodium-dev

# Alpine
apk add gcc musl-dev libsodium-dev

# macOS
brew install libsodium
```

## 2. Get the Server Source

```bash
# Clone the repo (or just copy the file)
git clone https://github.com/code3hr/cyxchat.git
cd cyxchat
```

The server source is at `tools/cyxchat-server.c` — a single self-contained C file.

## 3. Compile

```bash
gcc -O2 -Wall -o cyxchat-server tools/cyxchat-server.c -lsodium
```

## 4. Run

```bash
./cyxchat-server 7777
```

On first run, the server will:
1. Generate an Ed25519 keypair
2. Save it to `server_key.dat` (keep this file safe — it's your server's identity)
3. Print the public key hex

```
CyxChat Server (Bootstrap + Relay)
===================================

Generated new server identity
Server pubkey: 87a16820981e16be773d64a49ef434cb62c233abaf1785bfb5ed25affad7640b
  (Add this to client seed list for verification)

Listening on UDP port 7777
```

On subsequent runs, it loads the existing keypair from `server_key.dat`.

## 5. Run in Background (Production)

Using `screen`:
```bash
screen -dmS server bash -c './cyxchat-server 2>&1 | tee server.log'

# View logs
screen -r server
# Detach: Ctrl+A, then D
```

Using `systemd`:
```ini
# /etc/systemd/system/cyxchat-server.service
[Unit]
Description=CyxChat Bootstrap/Relay Server
After=network.target

[Service]
Type=simple
User=cyxchat
WorkingDirectory=/opt/cyxchat
ExecStart=/opt/cyxchat/cyxchat-server 7777
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now cyxchat-server
sudo journalctl -u cyxchat-server -f  # View logs
```

## 6. Firewall

Ensure UDP port 7777 is open:

```bash
# UFW
sudo ufw allow 7777/udp

# iptables
sudo iptables -A INPUT -p udp --dport 7777 -j ACCEPT

# Oracle Cloud: Add ingress rule in VCN Security List for UDP 7777
```

## Connecting Clients to Your Server

### Option A: Users Add Manually (No App Update)

Users can add your server in the app:

1. Open **Settings** → scroll to **Servers** section
2. Tap **Add**
3. Enter your server's `IP:PORT` (e.g., `203.0.113.50:7777`)
4. The server appears in the list and health checks begin

The server will be added as **unverified** (no Ed25519 pubkey check). It will still work for bootstrap and relay, but clients won't cryptographically verify the server's identity.

### Option B: Add to Seed List (Verified — Requires App Update)

For verified servers trusted by the project, add the server to the hardcoded seed list:

1. Edit `lib/src/server_registry.c`:

```c
static const cyxchat_seed_server_t SEED_SERVERS[] = {
    { "129.151.146.219:7777", "87a16820981e16be773d64a49ef434cb62c233abaf1785bfb5ed25affad7640b" },
    { "YOUR_IP:7777", "YOUR_PUBKEY_HEX" },
};
```

2. Rebuild the C library and Flutter app
3. Release a new app version

Seed servers are automatically loaded on connect and verified via Ed25519 challenge-response. The client sends a random 32-byte nonce, the server signs it, and the client verifies the signature against the hardcoded pubkey.

## Server Identity

- **Keypair**: Ed25519, stored in `server_key.dat` (64 bytes: 32 secret + 32 public)
- **Verification**: Challenge-response — client sends nonce, server signs it
- **Health checks**: Clients ping every 15 seconds, 3 missed pongs = unhealthy
- **Failover**: Clients auto-switch to the lowest-latency healthy server

### Backing Up Identity

```bash
# Backup
cp server_key.dat server_key.dat.bak

# Restore on new machine
cp server_key.dat.bak /opt/cyxchat/server_key.dat
```

If you lose `server_key.dat`, the server generates a new identity and the old pubkey in any seed lists becomes invalid.

## Server Capabilities

The server handles:

| Function | Description |
|----------|-------------|
| **Bootstrap** | Registers clients, returns peer lists for P2P discovery |
| **Relay** | Forwards messages between clients that can't establish direct P2P |
| **Health pong** | Responds to client health pings (0xF5 → 0xF6) |
| **Challenge response** | Signs client nonces for identity verification (0xF9 → 0xFA) |

## Docker (Alternative)

The Dockerfile needs updating for libsodium. Updated version:

```dockerfile
FROM alpine:3.19 AS builder
RUN apk add --no-cache gcc musl-dev libsodium-dev
WORKDIR /build
COPY cyxchat-server.c .
RUN gcc -O2 -Wall -o cyxchat-server cyxchat-server.c -lsodium

FROM alpine:3.19
RUN apk add --no-cache libsodium
WORKDIR /app
COPY --from=builder /build/cyxchat-server .
VOLUME /app/data
EXPOSE 7777/udp
ENTRYPOINT ["./cyxchat-server"]
CMD ["7777"]
```

```bash
docker build -t cyxchat-server .
docker run -d -p 7777:7777/udp -v cyxchat-data:/app/data --name cyxchat-server cyxchat-server
```

Use a volume to persist `server_key.dat` across container restarts.

## Troubleshooting

**"error while loading shared libraries: libsodium.so"**
```bash
sudo ldconfig  # Refresh library cache
```

**Clients can't connect**
- Check UDP 7777 is open: `nc -uzv YOUR_IP 7777`
- Check server is running: `pgrep -a cyxchat`
- Check logs: `tail -f server.log`

**Server generates new identity on every restart**
- Ensure `server_key.dat` is in the working directory where you run the server
- Check file permissions: `ls -la server_key.dat`
