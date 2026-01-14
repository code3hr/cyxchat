# Oracle Cloud Server Management

This document explains how to manage the CyxChat bootstrap server running on Oracle Cloud.

## Server Details

- **IP**: 129.151.146.219
- **Port**: 7777 (UDP)
- **SSH Key**: `ssh-key-2026-01-14.key` (in cyxchat/ directory)
- **Binary**: `cyxchat-server`

## SSH Connection

```bash
# Connect to server
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219

# Quick command execution (without interactive shell)
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "command here"
```

## SCP File Transfer

```bash
# Upload file to server
scp -i ssh-key-2026-01-14.key local_file ubuntu@129.151.146.219:~/

# Upload server source
scp -i ssh-key-2026-01-14.key tools/cyxchat-server.c ubuntu@129.151.146.219:~/

# Download file from server
scp -i ssh-key-2026-01-14.key ubuntu@129.151.146.219:~/remote_file ./local_destination

# Download server logs
scp -i ssh-key-2026-01-14.key ubuntu@129.151.146.219:~/server.log ./
```

## Building the Server

```bash
# SSH into server and compile
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219

# On server:
gcc -O2 -o cyxchat-server cyxchat-server.c
```

Or one-liner:
```bash
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "gcc -O2 -o cyxchat-server cyxchat-server.c"
```

## Running the Server

### Using screen (Recommended)

```bash
# Start server in detached screen session (no log file)
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "screen -dmS server ./cyxchat-server"

# Start server with screen AND log file (recommended)
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "screen -dmS server bash -c './cyxchat-server 2>&1 | tee server.log'"

# Attach to screen session to view output
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 -t "screen -r server"

# Detach from screen: Press Ctrl+A, then D

# List screen sessions
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "screen -ls"

# Kill screen session
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "screen -S server -X quit"
```

### Using nohup

```bash
# Start server with nohup (output to server.log)
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "nohup ./cyxchat-server > server.log 2>&1 &"

# Check if server is running
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "pgrep -f cyxchat-server"

# View last 50 lines of log
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "tail -50 server.log"

# Follow log in real-time
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "tail -f server.log"
```

### Stopping the Server

```bash
# Kill by name
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "pkill cyxchat-server"

# Kill by PID (if you know it)
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "kill PID"
```

## Common Operations

### Deploy New Version

Complete deployment workflow:
```bash
# 1. Upload new source
scp -i ssh-key-2026-01-14.key tools/cyxchat-server.c ubuntu@129.151.146.219:~/

# 2. Stop old server, compile, and start new one
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "pkill cyxchat-server; gcc -O2 -o cyxchat-server cyxchat-server.c && screen -dmS server ./cyxchat-server"
```

One-liner for quick deploy:
```bash
scp -i ssh-key-2026-01-14.key tools/cyxchat-server.c ubuntu@129.151.146.219:~/ && ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "pkill cyxchat-server; gcc -O2 -o cyxchat-server cyxchat-server.c && screen -dmS server ./cyxchat-server"
```

### Check Server Status

```bash
# Is server running?
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "pgrep -la cyxchat"

# Check port binding
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "ss -ulnp | grep 7777"

# Check firewall
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "sudo iptables -L -n | grep 7777"
```

### View Logs

```bash
# Last 100 lines
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "tail -100 server.log"

# Real-time monitoring
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "tail -f server.log"

# Search for specific messages
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "grep 'Relay' server.log"
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "grep 'register' server.log"
```

### Debugging

```bash
# Check if packets are reaching server
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "sudo tcpdump -i ens3 udp port 7777 -c 10"

# Use strace to see system calls
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "strace -f -e recvfrom,sendto ./cyxchat-server 2>&1 | head -100"

# Check server memory/CPU
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "top -b -n 1 | head -20"
```

## Oracle Cloud Network Configuration

If UDP packets aren't reaching the server, check:

1. **VCN Security List** (Oracle Cloud Console)
   - Navigate: Networking → Virtual Cloud Networks → VCN → Security Lists
   - Add Ingress Rule:
     - Source: 0.0.0.0/0
     - Protocol: UDP
     - Destination Port: 7777

2. **Instance Firewall (iptables)**
   ```bash
   # Allow UDP 7777
   ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "sudo iptables -I INPUT -p udp --dport 7777 -j ACCEPT"

   # Make persistent
   ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "sudo netfilter-persistent save"
   ```

## Troubleshooting

### Server Not Receiving Packets

1. Check if server is running:
   ```bash
   ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "pgrep -la cyxchat"
   ```

2. Verify port binding:
   ```bash
   ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "ss -ulnp | grep 7777"
   ```

3. Check Oracle VCN Security List (see above)

4. Check iptables:
   ```bash
   ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "sudo iptables -L INPUT -n | grep 7777"
   ```

5. Capture packets to verify they arrive:
   ```bash
   ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "sudo tcpdump -i ens3 udp port 7777 -c 5"
   ```

### Server Crashes / Exits

Check the log for errors:
```bash
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "tail -50 server.log"
```

Run in foreground to see output:
```bash
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 -t "./cyxchat-server"
```

### Struct Packing Issues

If registration packets appear to arrive but are rejected, it may be a struct packing issue. The server expects 35-byte registration packets. Check:
```bash
ssh -i ssh-key-2026-01-14.key ubuntu@129.151.146.219 "strace -e recvfrom ./cyxchat-server 2>&1 | grep 'recvfrom.*= [0-9]'"
```

If you see 35 bytes received but no log output, ensure `__attribute__((packed))` is used on all protocol structs.

## Environment Variables (Client)

Configure clients to use this server:

```
CYXWIZ_BOOTSTRAP=129.151.146.219:7777
CYXCHAT_RELAY=129.151.146.219:7777
```

Or in the Flutter app: Settings → Network → Bootstrap Server → `129.151.146.219:7777`
