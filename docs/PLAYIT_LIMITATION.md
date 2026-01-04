# Playit.gg Tunnel Limitation

## Summary

**Playit.gg UDP tunneling does NOT work** for CyxChat peer discovery because it masks real peer IP addresses.

## The Problem

CyxChat's bootstrap server works by:
1. Peer A registers with bootstrap, bootstrap records Peer A's IP:port
2. Peer B registers, bootstrap sends Peer A's IP:port to Peer B
3. Peer B connects directly to Peer A using that IP:port

With playit tunneling:
```
Peer A (176.205.45.138:52676)
    ↓ UDP packet
playit public (147.185.221.16:50841)
    ↓ tunnel
playit agent (localhost)
    ↓ forward
Bootstrap server (127.0.0.1:7777)
```

The bootstrap sees `127.196.148.59:xxxxx` (playit internal address) instead of Peer A's real public IP `176.205.45.138:52676`.

When bootstrap tells Peer B about Peer A, it gives the wrong (playit internal) address. Peer B cannot reach Peer A.

## Error Symptoms

```
[WARN] No shared key with destination 9999999999999999...
[ERROR] Failed to send message: error -14
```

Peers register successfully but never discover each other because the IP addresses are wrong.

## What Works

| Setup | Works? | Notes |
|-------|--------|-------|
| `127.0.0.1:7777` (localhost) | Yes | Both peers on same machine |
| LAN IP (e.g., `192.168.1.x:7777`) | Yes | Peers on same network |
| Public VPS with real IP | Yes | Bootstrap has real public IP |
| Playit UDP tunnel | No | Masks real peer IPs |
| ngrok TCP | No | CyxChat uses UDP, not TCP |

## Solutions for Remote Access

1. **VPS Deployment**: Run bootstrap server on a cloud VPS (DigitalOcean, Vultr, AWS, etc.) with a public IP

2. **Router Port Forwarding**: Forward UDP port 7777 to the machine running the bootstrap server

3. **Future Enhancement**: Modify protocol to include STUN-discovered public IP in registration packets (currently not implemented)

## Tested Configuration

- playit.gg agent v0.16.5
- Tunnel: `written-crowd.gl.at.ply.gg:50841 => 127.0.0.1:7777 (UDP)`
- Result: Bootstrap receives registrations but peer IPs are masked

## Date

2026-01-04
