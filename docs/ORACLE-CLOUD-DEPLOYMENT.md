# CyxChat Server Deployment on Oracle Cloud Free Tier

A complete guide to deploying the CyxChat bootstrap/relay server on Oracle Cloud's Always Free tier. This documents our actual deployment journey, including all challenges faced and solutions found.

## Overview

**Goal**: Run a CyxChat UDP server (port 7777) that anyone in the world can connect to.

**Final Result**: Server running at `129.151.146.219:7777`

**Cost**: $0 (Oracle Cloud Always Free Tier)

---

## Part 1: Why Oracle Cloud?

### Initial Attempt: Free VPS Hosting

We first tried freevpshostings.com which advertised "free VPS".

**Problem**: It wasn't actually a VPS - it was WordPress-only shared hosting with:
- No SSH access
- No root access
- No ability to run custom binaries
- Only WordPress sites

**Lesson**: "Free VPS" hosting often means shared web hosting, not actual virtual machines.

### Oracle Cloud Free Tier

Oracle offers genuinely free VMs that never expire:
- **VM.Standard.E2.1.Micro**: 1 OCPU, 1GB RAM (what we used)
- **VM.Standard.A1.Flex**: Up to 4 OCPUs, 24GB RAM (ARM-based, more powerful)
- Full root access
- Can run any software
- Persistent storage

---

## Part 2: Creating the Oracle Cloud VM

### Step 1: Create Oracle Cloud Account

1. Go to https://cloud.oracle.com
2. Click "Sign Up"
3. Complete registration (requires credit card for verification, but won't be charged for free tier)
4. Wait for account activation (usually instant)

### Step 2: Create VM Instance

1. Navigate to: **Compute** → **Instances** → **Create Instance**

2. Configure **Basic Information**:
   - Name: `cyxchat-server`
   - Compartment: (default)

3. Configure **Image and Shape**:
   - Image: **Ubuntu 22.04** (Canonical Ubuntu)
   - Shape: **VM.Standard.E2.1.Micro** (Always Free eligible)

4. Configure **Networking**:
   - Virtual Cloud Network: Create new or select existing
   - Subnet: Create new public subnet
   - **CRITICAL**: Check "Assign a public IPv4 address"

5. Configure **Add SSH Keys**:
   - Select "Generate a key pair for me"
   - Click "Save Private Key" - **SAVE THIS FILE SECURELY**
   - The private key downloads as `ssh-key-YYYY-MM-DD.key`

6. Click **Create**

### Step 3: If You Forgot Public IP

If you didn't enable public IP during creation:

1. Go to your instance details
2. Scroll to **Resources** → **Attached VNICs**
3. Click on the VNIC name
4. Go to **Resources** → **IPv4 Addresses**
5. Click the three dots (⋮) menu → **Edit**
6. Enable "Ephemeral Public IP"
7. Save

---

## Part 3: Server Setup

### Step 1: Connect via SSH

**Windows (PowerShell)**:
```powershell
# Fix key permissions (required on Windows)
icacls "D:\path\to\ssh-key.key" /inheritance:r /grant:r "$($env:USERNAME):(R)"

# Connect
ssh -i "D:\path\to\ssh-key.key" ubuntu@YOUR_PUBLIC_IP
```

**Linux/macOS**:
```bash
chmod 600 ~/path/to/ssh-key.key
ssh -i ~/path/to/ssh-key.key ubuntu@YOUR_PUBLIC_IP
```

### Step 2: Install Dependencies

```bash
sudo apt update
sudo apt install -y gcc
```

### Step 3: Upload Server Code

**From your local machine**:
```powershell
# Windows
scp -i "D:\path\to\ssh-key.key" "D:\dev\conspiracy\tools\cyxchat-server.c" ubuntu@YOUR_IP:~/
```

```bash
# Linux/macOS
scp -i ~/path/to/ssh-key.key ~/dev/conspiracy/tools/cyxchat-server.c ubuntu@YOUR_IP:~/
```

### Step 4: Compile the Server

```bash
gcc -O2 -o cyxchat-server cyxchat-server.c
```

### Step 5: Test Run

```bash
./cyxchat-server
# Should show: "CyxChat Bootstrap+Relay Server running on port 7777"
# Press Ctrl+C to stop
```

---

## Part 4: Systemd Service (Auto-Start)

### Create Service File

```bash
sudo nano /etc/systemd/system/cyxchat-server.service
```

Paste this content:
```ini
[Unit]
Description=CyxChat Bootstrap and Relay Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/home/ubuntu/cyxchat-server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable cyxchat-server
sudo systemctl start cyxchat-server

# Check status
sudo systemctl status cyxchat-server
```

**Expected output**:
```
● cyxchat-server.service - CyxChat Bootstrap and Relay Server
     Loaded: loaded (/etc/systemd/system/cyxchat-server.service; enabled)
     Active: active (running)
```

### Service Management Commands

```bash
sudo systemctl stop cyxchat-server      # Stop
sudo systemctl restart cyxchat-server   # Restart
sudo systemctl status cyxchat-server    # Check status
journalctl -u cyxchat-server -f         # View logs (live)
```

---

## Part 5: Firewall Configuration

**This was the most challenging part.** Oracle Cloud has TWO firewalls:
1. **Security Lists** (cloud-level, in Oracle Console)
2. **iptables** (VM-level, inside the instance)

Both must allow UDP port 7777.

### Challenge 1: Security List CIDR Errors

When adding ingress rules, we encountered:
```
The requested CIDR 0.0.0.0/0 is invalid prefix size
```

**Solution**: This was a UI bug. After multiple attempts with correct values, it eventually worked. Make sure to:
- Use exactly `0.0.0.0/0` for source CIDR
- Select "UDP" as IP Protocol
- Enter `7777` for destination port

### Challenge 2: Packets Not Reaching Server

Even with Security List configured, UDP packets weren't arriving.

**Diagnosis** - On the server:
```bash
sudo tcpdump -i ens3 udp port 7777
```

From local machine, send test packet (see Testing section). If tcpdump shows nothing, the cloud firewall is blocking.

**Solution**: Configure iptables on the VM itself:

```bash
# Allow UDP 7777 inbound
sudo iptables -I INPUT 1 -p udp --dport 7777 -j ACCEPT

# Make it persistent across reboots
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

### Complete Security List Configuration

1. Go to **Networking** → **Virtual Cloud Networks**
2. Click your VCN → **Security Lists** → **Default Security List**
3. Click **Add Ingress Rules**
4. Configure:
   - Source Type: CIDR
   - Source CIDR: `0.0.0.0/0`
   - IP Protocol: UDP
   - Destination Port Range: `7777`
5. Click **Add Ingress Rules**

### Verify Both Firewalls

**Cloud Security List**:
- Check in Oracle Console under VCN → Security Lists
- Should show UDP 7777 from 0.0.0.0/0

**VM iptables**:
```bash
sudo iptables -L INPUT -n -v | grep 7777
# Should show: ACCEPT udp -- 0.0.0.0/0 0.0.0.0/0 udp dpt:7777
```

---

## Part 6: Testing

### Test from Server Side

Monitor incoming packets:
```bash
sudo tcpdump -i ens3 udp port 7777
```

### Test from Client Side

**PowerShell (Windows)**:
```powershell
$udpClient = New-Object System.Net.Sockets.UdpClient
try {
    $udpClient.Connect("YOUR_SERVER_IP", 7777)
    # Send a register message (0xF0 prefix)
    $bytes = [byte[]](0xF0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34)
    $sent = $udpClient.Send($bytes, $bytes.Length)
    Write-Host "SUCCESS: Sent $sent bytes"
} catch {
    Write-Host "ERROR: $_"
} finally {
    $udpClient.Close()
}
```

**Expected tcpdump output on server**:
```
05:39:15.886634 ens3 In IP client.ip.port > 10.0.0.176.7777: UDP, length 35
```

If you see this, UDP is working end-to-end!

### Test with CyxChat App

1. Open CyxChat
2. Go to Settings → Network → Bootstrap Server
3. Enter: `YOUR_SERVER_IP:7777`
4. App should connect and show "Connected" status

---

## Troubleshooting

### SSH Connection Refused

```
Permission denied (publickey)
```

**Causes**:
- Wrong private key file
- Key permissions too open
- Wrong username (use `ubuntu`, not `root`)

**Fix**:
```powershell
# Windows - fix permissions
icacls "key.key" /inheritance:r /grant:r "$($env:USERNAME):(R)"
```

### Server Not Starting

Check logs:
```bash
journalctl -u cyxchat-server -n 50
```

Common issues:
- Port already in use: `sudo lsof -i :7777`
- Binary not found: Check path in service file
- Permission denied: Check user in service file

### UDP Packets Not Arriving

1. **Check Security List** - Is UDP 7777 from 0.0.0.0/0 allowed?
2. **Check iptables** - `sudo iptables -L INPUT -n | grep 7777`
3. **Check server is listening** - `sudo ss -ulnp | grep 7777`
4. **Check tcpdump** - `sudo tcpdump -i any udp port 7777`

### CIDR Validation Errors

Oracle's UI sometimes glitches. Try:
- Refreshing the page
- Using a different browser
- Waiting a few minutes
- Ensuring exact format: `0.0.0.0/0` (not `0.0.0.0/00` or variations)

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    INTERNET                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ UDP :7777
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Oracle Cloud Security List                      │
│              (Cloud Firewall - ALLOW UDP 7777)              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Oracle Cloud VM                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  iptables (VM Firewall - ALLOW UDP 7777)              │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  cyxchat-server (systemd service)                     │  │
│  │  - Listens UDP 7777                                    │  │
│  │  - Handles peer registration                           │  │
│  │  - Relays messages between peers                       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Cost Analysis

| Resource | Free Tier Limit | Our Usage |
|----------|-----------------|-----------|
| VM.Standard.E2.1.Micro | 2 instances | 1 instance |
| Block Storage | 200 GB | ~50 GB |
| Outbound Data | 10 TB/month | Minimal |
| Public IP | Included | 1 IP |

**Total monthly cost: $0**

---

## Security Recommendations

1. **Keep Ubuntu Updated**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Enable Automatic Security Updates**:
   ```bash
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure -plow unattended-upgrades
   ```

3. **Secure SSH Key**: Store your private key safely, never share it

4. **Monitor Logs**: Regularly check for suspicious activity:
   ```bash
   journalctl -u cyxchat-server --since "1 hour ago"
   ```

---

## Quick Reference

| Item | Value |
|------|-------|
| Server IP | `129.151.146.219` |
| Port | `7777` (UDP) |
| OS | Ubuntu 22.04 |
| Service | `cyxchat-server.service` |
| Binary | `/home/ubuntu/cyxchat-server` |
| SSH User | `ubuntu` |

### Common Commands

```bash
# Check server status
sudo systemctl status cyxchat-server

# View live logs
journalctl -u cyxchat-server -f

# Restart server
sudo systemctl restart cyxchat-server

# Test UDP connectivity
sudo tcpdump -i ens3 udp port 7777

# Check firewall rules
sudo iptables -L INPUT -n -v | grep 7777
```

---

*This guide was created during the actual deployment of CyxChat's first public server in January 2026.*
