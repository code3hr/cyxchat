# CyxChat P2P Messaging Test Guide

## Quick Start (Copy-Paste Ready)

### 1. Start Fresh
```powershell
# Kill all instances
Get-Process cyxchat -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process cyxchat-server -ErrorAction SilentlyContinue | Stop-Process -Force

# Start bootstrap server (native - Docker UDP has issues on Windows)
Start-Process "D:\dev\conspiracy\build\Debug\cyxchat-server.exe" -ArgumentList "7777"
```

### 2. Start Instance A
```powershell
cd D:\dev\conspiracy\cyxchat\app
flutter run -d windows
```
Wait for: `CyxChat: Bootstrap server = "127.0.0.1:7777"`

### 3. Start Instance B (new terminal)
```powershell
cd D:\dev\conspiracy\cyxchat\app
.\build\windows\x64\runner\Release\cyxchat.exe
```

### 4. Test
1. In Instance A: Settings → tap short ID → Copy Node ID
2. In Instance B: Contacts → + → Node ID tab → paste → Add
3. Send a message

---

## Prerequisites

1. Bootstrap server (use native, NOT Docker - Docker UDP forwarding has issues on Windows):
   ```powershell
   # Start native server:
   D:\dev\conspiracy\build\Debug\cyxchat-server.exe 7777

   # Server should show:
   # Listening on UDP port 7777
   ```

## Step-by-Step Test Process

### Step 1: Close All Running Instances
Close both CyxChat windows completely.

### Step 2: Start Instance A (Debug)
```bash
cd D:\dev\conspiracy\cyxchat\app
flutter run -d windows
```

Wait for: `[INFO] Router started`

### Step 3: Configure Instance A
1. Go to **Settings** (gear icon, bottom nav)
2. Scroll to **Network** section
3. Tap **Bootstrap Server**
4. Enter: `127.0.0.1:7777`
5. Tap **Save**
6. **IMPORTANT: Close and restart the app** (the setting only applies on startup)

### Step 4: Restart Instance A
Press `q` in the terminal to quit, then run again:
```bash
flutter run -d windows
```

Look for these logs:
```
[INFO] Router started
[INFO] Bootstrap: Registered with server
```

### Step 5: Get Instance A's Node ID
1. Go to **Settings**
2. Tap the short ID badge (e.g., `b4b7b7b7`) in the profile card
3. Tap **Copy Node ID**
4. Paste it somewhere (notepad) - you'll need this

### Step 6: Build and Start Instance B
In a NEW terminal:
```bash
cd D:\dev\conspiracy\cyxchat\app
flutter build windows --dart-define=INSTANCE_ID=2
.\build\windows\x64\runner\Release\cyxchat.exe
```

### Step 7: Configure Instance B
1. Go to **Settings** → **Network** → **Bootstrap Server**
2. Enter: `127.0.0.1:7777`
3. Tap **Save**
4. **Close the app completely**

### Step 8: Restart Instance B
```bash
.\build\windows\x64\runner\Release\cyxchat.exe
```

Look for:
```
[INFO] Router started
[INFO] Bootstrap: Registered with server
```

### Step 9: Add Contact in Instance B
1. Go to **Contacts** tab
2. Tap **+** button (Add Contact)
3. Go to **Node ID** tab (last tab)
4. Paste Instance A's Node ID (64 characters)
5. Enter display name: "Instance A"
6. Tap **Add Contact**

### Step 10: Send Message
1. Chat screen opens automatically
2. Type a message
3. Tap send

### Step 11: Check Instance A
- The message should appear in Instance A's chat list
- If using debug mode, check terminal for logs

## Expected Logs (Success)

**Sender (Instance B):**
```
[INFO] Bootstrap: Registered with server
[INFO] Sending message to b4b7b7b7...
```

**Receiver (Instance A):**
```
[INFO] Bootstrap: Registered with server
[INFO] Received message from 60606060...
ChatService: Incoming message saved
```

## Troubleshooting

### "No bootstrap servers configured"
- You changed the setting but didn't restart the app
- Close app completely and restart

### "No shared key with destination"
- Peers haven't discovered each other yet
- Both apps must be registered with the same bootstrap server
- Check both apps show "Bootstrap: Registered with server"

### "Send failed"
- Destination peer not online
- Bootstrap server not running
- Firewall blocking UDP port 7777

### No messages appearing
- Check if the conversation is in the Chats list
- Pull down to refresh
- Check terminal logs for errors

## Node IDs for Reference

| Instance | Node ID (first 16 chars) |
|----------|--------------------------|
| A (Debug) | b4b7b7b7b7b7b7b7... |
| B (Release) | 6060606060606060... |

## Quick Reset

If things aren't working, start fresh:

1. Stop all apps
2. Delete databases:
   - Instance A: `%APPDATA%\..\Local\cyxchat\cyxchat.db`
   - Instance B: `%APPDATA%\..\Local\cyxchat\cyxchat_2.db`
3. Restart server: `Get-Process cyxchat-server | Stop-Process; D:\dev\conspiracy\build\Debug\cyxchat-server.exe 7777`
4. Follow steps from beginning

## Docker Issues (Windows)

Docker Desktop on Windows has known issues with UDP port forwarding to localhost.
The container may listen on port 7777 but UDP packets sent to 127.0.0.1:7777 don't reach it.
**Use the native server instead: `D:\dev\conspiracy\build\Debug\cyxchat-server.exe 7777`**

---

## Automated Tests

### Python Test Suite (Connection Progress)

Tests the real-time connection progress callback system.

```bash
# Prerequisites: Build C library first
cd cyxchat/lib
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release

# Copy dependencies (Windows)
cp vcpkg/packages/libsodium_x64-windows/bin/libsodium.dll lib/build/Release/
cp app/miniupnpc.dll lib/build/Release/

# Run tests
cd tests
python test_connection_progress.py --timeout 5
```

**Expected Output:**
```
============================================================
CyxChat Connection Progress Callback Test Suite
============================================================
[OK] Loaded library: ...\cyxchat.dll

TEST 1: Callback Registration
[OK] Callback registered successfully

TEST 2: Connect Fires LOOKUP_STARTED Event
  -> Event: LOOKUP_STARTED (peer: fa84626b..., retry: 0/10, fail: NONE)
  -> Event: HOLE_PUNCH_START (peer: fa84626b..., retry: 0/10, fail: NONE)
  -> Event: ANNOUNCE_SENT (peer: fa84626b..., retry: 0/10, fail: NONE)
[OK] First event is LOOKUP_STARTED

...

TEST SUMMARY
  [PASS]: callback_registration
  [PASS]: connect_fires_event
  [PASS]: event_sequence
  [PASS]: retry_increments
  [PASS]: input_validation
  [PASS]: thread_safety

  6/6 tests passed
```

See [tests/TEST_CONNECTION_PROGRESS.md](tests/TEST_CONNECTION_PROGRESS.md) for detailed documentation.

### C Library Unit Tests

```bash
cd cyxchat/lib
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

---

## Testing Connection Progress UI

The connection progress feature shows real-time status during peer connections.

### What to Look For

| Phase | UI Display | Color |
|-------|------------|-------|
| Querying | "Querying network..." | Orange |
| Found | "Found peer, exchanging keys..." | Orange |
| Keys | "Exchanging keys (2/10)..." | Orange |
| Connecting | "Keys exchanged, connecting..." | Orange |
| P2P | "Secured (direct P2P)" | Green |
| Relay | "Secured (via relay)" | Blue |
| Failed | "Failed: Peer appears offline" | Red |

### Test Scenarios

#### Scenario 1: Successful P2P Connection
1. Start two instances on same network
2. Add contact in Instance B
3. **Observe:** Progress through all phases to "Secured (direct P2P)"

#### Scenario 2: Connection Failure
1. Start app without bootstrap server
2. Add contact with random node ID
3. **Observe:** "Querying network..." → "Failed: Network lookup timed out"

#### Scenario 3: Retry Count Display
1. Add contact for offline peer
2. **Observe:** "Exchanging keys (1/10)..." → (2/10) → ... → "Failed: Key exchange timed out"

#### Scenario 4: Contacts Screen Indicators
1. Add multiple contacts
2. **Observe:** Presence dots show:
   - Green = Connected (P2P)
   - Blue = Connected (Relay)
   - Grey = Offline
   - Spinner = Connecting

---

## CI/CD Integration

```yaml
# GitHub Actions example
name: Test Suite

on: [push, pull_request]

jobs:
  test-c-library:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: sudo apt-get install -y libsodium-dev
      - name: Build
        run: |
          cd cyxchat/lib
          cmake -B build
          cmake --build build
      - name: Test
        run: ctest --test-dir cyxchat/lib/build --output-on-failure

  test-python:
    runs-on: ubuntu-latest
    needs: test-c-library
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Run Python tests
        run: |
          cd cyxchat/tests
          python test_connection_progress.py --timeout 5
```
