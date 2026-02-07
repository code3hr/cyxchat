# UPnP + NAT-PMP Integration Plan for CyxChat

## Overview

Add UPnP (Universal Plug and Play) IGD and NAT-PMP (Apple's protocol) support to automatically request port forwarding from routers, reducing connection latency and improving P2P success rate.

## Design Decisions

- **Default behavior:** Enabled by default (no user opt-in required)
- **Protocols:** Both UPnP IGD and NAT-PMP (miniupnpc supports both)
- **Platforms:** Windows, Linux, macOS, and Android

## Current NAT Traversal Flow

```
1. STUN Discovery (public IP:port)
2. Bootstrap Registration
3. Hole Punch (5 packets @ 50ms intervals)
4. Wait 5 seconds
5. Relay Fallback (if hole punch fails)
```

## Proposed Flow with UPnP

```
1. STUN Discovery (public IP:port)
2. [NEW] UPnP IGD Discovery + Port Mapping
   ├─ Success: Skip hole punch, direct connection ready
   └─ Failure: Continue to hole punch
3. Bootstrap Registration
4. Hole Punch (if UPnP failed)
5. Relay Fallback (if both fail)
```

## Benefits

| Scenario | Current | With UPnP |
|----------|---------|-----------|
| Cone NAT with UPnP router | 5s hole punch delay | <1s direct mapping |
| Symmetric NAT | Relay only | Relay (UPnP won't help) |
| No NAT | Instant | Instant (unchanged) |

---

## Implementation Plan

### Step 1: Add miniupnpc Dependency

**Files:**
- `D:\dev\conspiracy\CMakeLists.txt` (root)
- `D:\dev\conspiracy\cyxchat\lib\CMakeLists.txt`

**Changes:**
```cmake
# Add option
option(CYXWIZ_ENABLE_UPNP "Enable UPnP port mapping" ON)

# Find miniupnpc
if(CYXWIZ_ENABLE_UPNP)
    find_package(miniupnpc QUIET)
    if(miniupnpc_FOUND)
        add_definitions(-DCYXWIZ_HAS_UPNP)
    endif()
endif()
```

**Library:** miniupnpc (cross-platform, lightweight, ~3000 LOC)
- Windows: vcpkg install miniupnpc
- Linux: apt install libminiupnpc-dev
- macOS: brew install miniupnpc

---

### Step 2: Create UPnP Module

**New File:** `D:\dev\conspiracy\src\transport\upnp.c`

```c
#include "cyxwiz/transport.h"

#ifdef CYXWIZ_HAS_UPNP
#include <miniupnpc/miniupnpc.h>
#include <miniupnpc/upnpcommands.h>

typedef struct {
    struct UPNPUrls urls;
    struct IGDdatas data;
    char lan_addr[64];
    char wan_addr[64];
    uint16_t external_port;
    uint16_t internal_port;
    uint64_t lease_expiry_ms;
    bool mapping_active;
} cyxwiz_upnp_state_t;

// Discover UPnP IGD on local network
cyxwiz_error_t cyxwiz_upnp_discover(cyxwiz_upnp_state_t *state);

// Request port mapping (internal_port -> external_port)
cyxwiz_error_t cyxwiz_upnp_add_mapping(
    cyxwiz_upnp_state_t *state,
    uint16_t internal_port,
    uint16_t external_port,  // 0 = same as internal
    uint32_t lease_seconds   // 0 = permanent (not recommended)
);

// Remove port mapping
cyxwiz_error_t cyxwiz_upnp_remove_mapping(cyxwiz_upnp_state_t *state);

// Check if lease needs renewal
bool cyxwiz_upnp_needs_renewal(cyxwiz_upnp_state_t *state, uint64_t now_ms);

// Renew lease
cyxwiz_error_t cyxwiz_upnp_renew(cyxwiz_upnp_state_t *state);

#endif
```

**New Header:** `D:\dev\conspiracy\include\cyxwiz\upnp.h`

---

### Step 3: Integrate into UDP Transport

**File:** `D:\dev\conspiracy\src\transport\udp.c`

**Add to state struct (~line 75):**
```c
typedef struct {
    // ... existing fields ...

    #ifdef CYXWIZ_HAS_UPNP
    cyxwiz_upnp_state_t upnp;
    bool upnp_attempted;
    bool upnp_success;
    #endif
} cyxwiz_udp_state_t;
```

**Modify transport init (~line 200):**
```c
static cyxwiz_error_t udp_init(void *driver_data, ...) {
    // ... existing STUN init ...

    #ifdef CYXWIZ_HAS_UPNP
    // Try UPnP after socket is created
    cyxwiz_error_t upnp_err = cyxwiz_upnp_discover(&state->upnp);
    if (upnp_err == CYXWIZ_OK) {
        upnp_err = cyxwiz_upnp_add_mapping(
            &state->upnp,
            state->local_port,
            0,      // Same external port
            3600    // 1 hour lease
        );
        state->upnp_success = (upnp_err == CYXWIZ_OK);
    }
    state->upnp_attempted = true;
    #endif

    // Continue with STUN...
}
```

**Modify shutdown (~line 380):**
```c
static void udp_shutdown(void *driver_data) {
    #ifdef CYXWIZ_HAS_UPNP
    if (state->upnp_success) {
        cyxwiz_upnp_remove_mapping(&state->upnp);
    }
    #endif
    // ... existing cleanup ...
}
```

---

### Step 4: Add UPnP Lease Renewal to Poll

**File:** `D:\dev\conspiracy\src\transport\udp.c`

**In udp_poll() (~line 1100):**
```c
static cyxwiz_error_t udp_poll(void *driver_data, uint64_t now_ms) {
    // ... existing poll code ...

    #ifdef CYXWIZ_HAS_UPNP
    // Renew UPnP lease 5 minutes before expiry
    if (state->upnp_success &&
        cyxwiz_upnp_needs_renewal(&state->upnp, now_ms)) {
        cyxwiz_upnp_renew(&state->upnp);
    }
    #endif

    return CYXWIZ_OK;
}
```

---

### Step 5: Expose UPnP Status to Application

**File:** `D:\dev\conspiracy\cyxchat\lib\include\cyxchat\connection.h`

**Extend network status struct (~line 63):**
```c
typedef struct {
    // ... existing fields ...

    int upnp_available;         /* UPnP IGD found on network */
    int upnp_mapping_active;    /* Port mapping established */
    uint16_t upnp_external_port; /* Mapped external port */
    uint32_t upnp_lease_remaining_sec; /* Seconds until lease expires */
} cyxchat_network_status_t;
```

**File:** `D:\dev\conspiracy\cyxchat\lib\src\connection.c`

**Update cyxchat_conn_get_network_status():**
```c
cyxwiz_error_t cyxchat_conn_get_network_status(
    cyxchat_conn_t *ctx,
    cyxchat_network_status_t *status
) {
    // ... existing code ...

    #ifdef CYXWIZ_HAS_UPNP
    cyxwiz_udp_state_t *udp = get_udp_state(ctx->transport);
    status->upnp_available = udp->upnp_attempted;
    status->upnp_mapping_active = udp->upnp_success;
    if (udp->upnp_success) {
        status->upnp_external_port = udp->upnp.external_port;
        status->upnp_lease_remaining_sec =
            (udp->upnp.lease_expiry_ms - now_ms) / 1000;
    }
    #endif

    return CYXCHAT_OK;
}
```

---

### Step 6: Update FFI Bindings

**File:** `D:\dev\conspiracy\cyxchat\app\lib\ffi\bindings.dart`

**Add UPnP fields to NetworkStatus class:**
```dart
class NetworkStatus {
  // ... existing fields ...

  final bool upnpAvailable;
  final bool upnpMappingActive;
  final int upnpExternalPort;
  final int upnpLeaseRemainingSec;
}
```

---

### Step 7: Update Flutter UI (Optional)

**File:** `D:\dev\conspiracy\cyxchat\app\lib\screens\settings_screen.dart`

**Add UPnP status display in network section:**
```dart
ListTile(
  title: Text('UPnP Status'),
  subtitle: Text(
    networkStatus.upnpMappingActive
      ? 'Port ${networkStatus.upnpExternalPort} mapped (${networkStatus.upnpLeaseRemainingSec}s remaining)'
      : networkStatus.upnpAvailable
        ? 'Available but not mapped'
        : 'Not available'
  ),
  leading: Icon(
    networkStatus.upnpMappingActive
      ? Icons.check_circle
      : Icons.info_outline,
    color: networkStatus.upnpMappingActive
      ? Colors.green
      : Colors.grey,
  ),
),
```

---

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `include/cyxwiz/upnp.h` | CREATE | UPnP API header |
| `src/transport/upnp.c` | CREATE | UPnP implementation |
| `CMakeLists.txt` | MODIFY | Add miniupnpc dependency |
| `src/transport/udp.c` | MODIFY | Integrate UPnP into transport |
| `cyxchat/lib/include/cyxchat/connection.h` | MODIFY | Add UPnP status fields |
| `cyxchat/lib/src/connection.c` | MODIFY | Expose UPnP status |
| `cyxchat/app/lib/ffi/bindings.dart` | MODIFY | Add UPnP to FFI |
| `cyxchat/app/lib/screens/settings_screen.dart` | MODIFY | Display UPnP status |

---

## Testing Plan

1. **Unit Test:** UPnP discovery and mapping functions
2. **Integration Test:** Full connection flow with UPnP enabled
3. **Manual Test:**
   - Router with UPnP enabled → verify port mapping created
   - Router with UPnP disabled → verify graceful fallback to hole punch
   - Lease expiry → verify automatic renewal

---

## Rollback Strategy

UPnP is optional (`CYXWIZ_ENABLE_UPNP` CMake option). If issues arise:
1. Disable at compile time: `-DCYXWIZ_ENABLE_UPNP=OFF`
2. All existing NAT traversal logic unchanged
3. Zero impact on relay fallback

---

## Dependencies

- **miniupnpc** library (cross-platform, supports both UPnP IGD and NAT-PMP)
  - Windows: `vcpkg install miniupnpc`
  - Linux: `apt install libminiupnpc-dev`
  - macOS: `brew install miniupnpc`
  - Android: Build from source with NDK (see below)

---

## Android Build Instructions

**Step 1: Download miniupnpc source**
```bash
git clone https://github.com/miniupnp/miniupnp.git
cd miniupnp/miniupnpc
```

**Step 2: Create Android CMake toolchain**
```bash
# In cyxchat/android_build/
mkdir -p miniupnpc-android
cd miniupnpc-android

# Build for arm64-v8a
cmake ../../../miniupnp/miniupnpc \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-21 \
  -DUPNPC_BUILD_STATIC=ON \
  -DUPNPC_BUILD_SHARED=OFF \
  -DUPNPC_BUILD_TESTS=OFF \
  -DUPNPC_BUILD_SAMPLE=OFF

cmake --build . --config Release
```

**Step 3: Copy to Android libs**
```bash
cp libminiupnpc.a ../../app/android/app/src/main/jniLibs/arm64-v8a/
```

**Step 4: Update Android CMakeLists.txt**
```cmake
# In cyxchat/lib/CMakeLists.txt (Android section)
if(ANDROID)
    find_library(MINIUPNPC_LIB miniupnpc
        PATHS ${CMAKE_SOURCE_DIR}/../app/android/app/src/main/jniLibs/${ANDROID_ABI})
    target_link_libraries(cyxchat ${MINIUPNPC_LIB})
endif()
```

---

## NAT-PMP Support

miniupnpc automatically tries NAT-PMP when UPnP IGD fails. The library flow:

```
1. UPNP_GetValidIGD() - Try UPnP IGD discovery
2. If UPnP fails, try NAT-PMP (Apple Time Capsule, AirPort, etc.)
3. UPNP_AddPortMapping() works for both protocols
```

No additional code needed - miniupnpc handles protocol selection internally.

---

*Document version: 1.0*
*Created: February 2026*
*Status: Planned (Not Implemented)*
*Branch: feature/upnp-nat-pmp*
