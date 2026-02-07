# Connection Progress Callback Test Suite

This document describes how to test the real-time connection progress feedback system.

## Overview

The connection progress system provides granular feedback during the P2P connection lifecycle:

```
LOOKUP_STARTED → PEER_FOUND → ANNOUNCE_SENT → ANNOUNCE_RETRY(n) →
KEY_RECEIVED → HOLE_PUNCH_START → CONNECTED_P2P/CONNECTED_RELAY
                                              ↓
                                           FAILED (with reason)
```

## Prerequisites

### 1. Build the C Library

```bash
cd cyxchat/lib
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

### 2. Verify Library Location

The test script looks for the library in these locations:
- `lib/build/Release/cyxchat.dll` (Windows)
- `lib/build/libcyxchat.so` (Linux)
- `lib/build/libcyxchat.dylib` (macOS)

### 3. (Optional) Start Bootstrap Server

For full integration testing with actual network events:

```bash
# Using Docker
docker run -d -p 7777:7777/udp --name cyxchat-server cyxchat-server

# Or run locally
cd tools && ./cyxchat-server
```

## Running the Tests

### Basic Test (Offline)

```bash
cd cyxchat/tests
python test_connection_progress.py
```

### With Custom Library Path

```bash
python test_connection_progress.py --lib /path/to/cyxchat.dll
```

### With Bootstrap Server

```bash
python test_connection_progress.py --bootstrap 192.168.1.100:7777
```

### Extended Timeout Test

```bash
python test_connection_progress.py --timeout 30
```

## Test Cases

### Test 1: Callback Registration
Verifies the progress callback can be registered without crashing.

**Expected:** No crash, callback successfully set.

### Test 2: Connect Fires LOOKUP_STARTED Event
Verifies calling `connect()` triggers a `LOOKUP_STARTED` event.

**Expected:** First event received is `LOOKUP_STARTED`.

### Test 3: Event Sequence During Timeout
Monitors event sequence when connecting to an unreachable peer.

**Expected Sequence:**
1. `LOOKUP_STARTED`
2. (optional) `PEER_FOUND`
3. `ANNOUNCE_SENT`
4. `ANNOUNCE_RETRY` (multiple times)
5. `FAILED` with reason code

### Test 4: Retry Count Increments
Verifies `ANNOUNCE_RETRY` events have incrementing retry counts.

**Expected:** retry_num increases: 1, 2, 3, ...

### Test 5: Input Validation
Tests edge cases like all-zero and all-0xFF peer IDs.

**Expected:** No crash, values clamped to valid range.

### Test 6: Thread Safety
Runs concurrent poll and connect operations.

**Expected:** No race condition crashes.

## Expected Output

```
============================================================
CyxChat Connection Progress Callback Test Suite
============================================================
✓ Loaded library: D:\Dev\conspiracy\cyxchat\lib\build\Release\cyxchat.dll

Test Configuration:
  Bootstrap: 127.0.0.1:7777
  Local ID: a1b2c3d4e5f67890...
  Test Peer: 1234567890abcdef...
✓ Initialized connection context
  Bootstrap: 127.0.0.1:7777
  Local ID: a1b2c3d4e5f67890...

============================================================
TEST 1: Callback Registration
============================================================
✓ Callback registered successfully

============================================================
TEST 2: Connect Fires LOOKUP_STARTED Event
============================================================
  Connecting to peer: 1234567890abcdef...
  → Event: LOOKUP_STARTED (peer: 12345678..., retry: 0/10, fail: NONE)
✓ First event is LOOKUP_STARTED

...

============================================================
TEST SUMMARY
============================================================
  ✓ PASS: callback_registration
  ✓ PASS: connect_fires_event
  ✓ PASS: event_sequence
  ✓ PASS: retry_increments
  ✓ PASS: input_validation
  ✓ PASS: thread_safety

  6/6 tests passed
```

## Manual Flutter App Testing

### Test Scenario 1: Fresh Connection

1. Start bootstrap server
2. Run two app instances (A and B)
3. In Instance A: Go to Contacts → Add Contact → Enter B's node ID
4. **Observe in A:** Status should progress through:
   - "Querying network..."
   - "Found peer, exchanging keys..."
   - "Exchanging keys (1/10)..."
   - "Keys exchanged, connecting..."
   - "Secured (direct P2P)" ✓

### Test Scenario 2: Connection Failure

1. Start app without bootstrap server running
2. Add a fake contact with random node ID
3. **Observe:** Status should show:
   - "Querying network..."
   - "Failed: Network lookup timed out"

### Test Scenario 3: Retry Progression

1. Start bootstrap server
2. Add contact for offline peer
3. **Observe:** Status should show:
   - "Exchanging keys (1/10)..."
   - "Exchanging keys (2/10)..."
   - ... up to 10/10
   - "Failed: Key exchange timed out"

### Test Scenario 4: Relay Fallback

1. Both peers behind symmetric NAT (no direct P2P possible)
2. Connect to peer
3. **Observe:** Status should show:
   - "Connecting..." (hole punch attempt)
   - "Secured (via relay)" with blue color

## Verifying C Library Events

To verify events fire correctly from the C library, enable debug logging:

```bash
# Set environment variable before running
export CYXWIZ_LOG_LEVEL=DEBUG

# Run test
python test_connection_progress.py
```

Expected C library output:
```
[INFO] [Connection] Peer found: 1234567890abcdef...
[INFO] [Connection] Key exchange complete: 1234567890abcdef...
[INFO] [Connection] Connected P2P: 1234567890abcdef...
```

## Troubleshooting

### "Could not find cyxchat library"
- Ensure library is built: `cmake --build build`
- Specify path: `--lib /path/to/cyxchat.dll`

### "No events received"
- Bootstrap server may not be running
- Firewall may be blocking UDP port 7777
- Test without network (some tests still pass)

### "Callback not firing"
- Check `cyxchat_conn_set_on_progress` was called
- Verify `cyxchat_conn_poll` is being called regularly
- Check for null context

### Thread Safety Issues
- Ensure callback pointer is stored (prevent garbage collection)
- Check for race between set_on_progress and poll

## Code Coverage

| Component | Covered |
|-----------|---------|
| `fire_progress_event()` | ✓ |
| Event enum validation | ✓ |
| Fail reason validation | ✓ |
| Retry count bounds | ✓ |
| Null pointer guards | ✓ |
| Callback registration | ✓ |
| Callback invocation | ✓ |

## Integration with CI

```yaml
# GitHub Actions example
test-connection-progress:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v3
    - name: Build C library
      run: |
        cd cyxchat/lib
        cmake -B build
        cmake --build build
    - name: Run Python tests
      run: |
        cd cyxchat/tests
        python test_connection_progress.py --timeout 5
```
