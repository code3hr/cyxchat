# CyxChat TODO

## High Priority

### IP Change / Network Transition Handling

**Problem:** When a user changes networks (WiFi → mobile, moves location), their public IP changes and the UDP hole punch breaks. Currently, the connection dies and requires manual reconnection.

**Current behavior:**
1. STUN discovery done once at startup
2. IP change breaks hole punch path
3. Peer timeout (30s) marks connection as disconnected
4. User must manually reconnect

**Required implementation:**

1. **Periodic STUN refresh**
   - Check public IP every 30-60 seconds
   - Compare with last known IP
   - Detect IP changes promptly

2. **Re-registration flow**
   - When IP changes, re-register with bootstrap server
   - Update DNS record with new STUN address
   - Notify active peers of new address

3. **Seamless reconnection**
   - Re-punch holes with all active peers
   - Use relay as bridge during transition (no message loss)
   - Restore direct connection when new hole punch succeeds

4. **UI notification**
   - Show "Reconnecting..." status during transition
   - Don't mark messages as failed during brief transitions

**Files to modify:**
- `lib/src/connection.c` - Add periodic STUN, IP change detection
- `lib/src/relay.c` - Bridge mode during transition
- `lib/include/cyxchat/connection.h` - New status codes
- `app/lib/providers/connection_provider.dart` - Handle reconnecting state

**Estimated complexity:** Medium-High

---

## Medium Priority

### Offline Message Queue
- Queue messages when peer is offline
- Deliver when peer comes back online
- Persist queue to local storage

### Message Delivery Receipts
- Sent/Delivered/Read status
- Retry failed deliveries

### Group Chat Improvements
- Key rotation on member changes
- Admin controls
- Member list sync

---

## Low Priority

### Performance
- Message pagination for large conversations
- Lazy load older messages
- Connection pooling

### UX Improvements
- Typing indicators
- Online/offline status
- Last seen timestamps
