# CyxChat Android Live Triage Tracker

This tracker covers the current Android device-to-device reliability and security audit. Keep fixes small, prove each one with logs/tests, then commit and push only the touched files for that fix.

## Live Devices

- Device A: `43f9d645-9174-4df1-b62e-7decfcd6bd47`
- Device B: `95a30235-8c5d-4911-9050-c57a8dbcb91a`
- Oracle bootstrap/relay: `129.151.146.219:7777`

Native routing pads UUID node IDs to 32 bytes, so server-side searches should include:

- A UUID hex: `43f9d64591744df1b62e7decfcd6bd47`
- A native padded hex: `43f9d64591744df1b62e7decfcd6bd4700000000000000000000000000000000`
- B UUID hex: `95a302358c5d49119050c57a8dbcb91a`
- B native padded hex: `95a302358c5d49119050c57a8dbcb91a00000000000000000000000000000000`

## Reported Symptoms

- Messages from A to B can be delayed or never appear on B.
- Messaging can become one-way, where one device receives but the other direction does not.
- UI can stay on "establishing connection" even while some messages still pass.
- Connections are re-established too late, often when the user opens a chat or tries to send, instead of being maintained after app start/resume/network recovery.
- Android inactive/background app does not reliably show notifications.
- Audio calls and video calls do not work reliably.
- When a call drops, the app can show a blank screen instead of returning to a valid chat/home/call-ended state.
- Large file transfers still do not complete even after the receiver accepts.
- Hold-to-record audio button is not active.
- Architecture is hard to reason about across bootstrap, relay, chat ACKs, notifications, and WebRTC signaling.
- Security needs proof: determine whether Oracle relay/server or a network observer can capture plaintext messages, or only metadata/encrypted packets.

## Initial Read

- `ConnectionProvider.isOnline` currently depends on bootstrap health, not on per-peer message reachability.
- Message delivery has multiple layers: Dart queue/status, native pending/ACK/retry, onion routing, direct UDP, relay fallback, and receive polling.
- Local notifications are process-bound; Android background/killed notifications need native background delivery, a foreground service, or push-style delivery. Dart local notifications alone cannot guarantee delivery if the app is suspended.
- Calls depend on the same peer signaling path for offer/answer/ICE plus platform media permissions and WebRTC ICE state.
- Oracle `cyxchat-server` is part of the production path. Current logs show both Android devices registering, but also repeated offline queueing and large delayed queue delivery bursts, so server relay reliability must be fixed and redeployed, not treated as external.
- The relay should not see plaintext message bodies if encryption is correct, but it can still observe IPs, timing, packet sizes, registration, relay usage, and likely communication metadata.

## Workstreams

1. Evidence capture
   - Check Oracle server process, UDP binding, and recent logs.
   - Search server logs for A/B IDs in UUID, undashed hex, padded hex, and short-prefix forms.
   - Run one PC instance with visible logs and have a mobile device message/call it.
   - Capture app logs around send attempt, native message ID, route, ACK, receive poll, notification state, and call signal state.

2. Connection-state fix
   - Separate app online/bootstrap state from peer delivery state.
   - UI should show bootstrap, peer key, route, relay/direct, and delivery status without blocking on a stale "establishing connection" label.
   - Reconnect only when actually offline, after app resume, or after network recovery; do not repeatedly reset established connections.
   - Warm-connect known contacts in the background so opening a chat does not spend time establishing the route/key.
   - Done when the UI no longer reports a false stuck state while messages can flow.
   - Status: background warm-connect is implemented and pushed; chat header no longer shows a blocking "establishing connection" state while bootstrap is online and peer route warming is passive.
   - Current fix in progress: app online state now follows the initialized local network stack, while bootstrap ACK is exposed as a diagnostic detail; reconnect no longer tears down a working native connection only because the ACK flag is false.

3. Oracle server relay fix and redeploy
   - Audit the active Oracle `cyxchat-server.c` against the repo/source-of-truth server code.
   - Fix relay ACK tracking, peer expiry, offline queue delivery, queue caps, and large-file relay behavior with the smallest server-side changes.
   - Add server logging that shows message hash/route/queue/ACK outcomes without logging plaintext payloads.
   - Build locally or on Oracle, upload the new `cyxchat-server`, restart the systemd service, and verify UDP `7777` is bound.
   - Done when A/B logs show stable registration, no false offline churn during active use, and queued messages drain predictably.
   - Status: local source-of-truth server was patched, pushed in the parent repo, deployed to Oracle, restarted, and verified active on UDP `7777`.

4. Message-delivery fix
   - Prove whether lost messages are failing before send, at native retry, at relay/direct route, at ACK clearing, or at receiver polling/persistence.
   - Validate both directions independently; A -> B and B -> A must both deliver.
   - Add focused logging only where the path lacks evidence.
   - Fix the smallest broken layer, then add a regression test where practical.
   - Done when A/B logs show message ID sent, routed, received, persisted, displayed, and ACKed.
   - Status: native text ACK now waits for Dart persistence, incoming native message IDs are idempotent, and duplicate relay/direct deliveries do not create duplicate visible rows.

5. Android notification fix
   - Confirm foreground, background, and killed-app behavior separately.
   - If messages only arrive while the process is alive, design the smallest Android-native background strategy.
   - Done when inactive-app notifications work for received messages under a documented Android state.

6. Audio/video call fix
   - Trace offer, answer, ICE candidates, call state transitions, permission checks, and media acquisition.
   - Make call signaling observable before changing transport.
   - Fix dropped-call navigation/state so the UI never lands on a blank screen.
   - Done when A/B or mobile/PC call setup reaches connected media or reports a precise failure reason.

7. Large file transfer fix
   - Trace transfer invite, receiver accept, direct/relay route selection, chunk send, chunk ACK, missing-chunk retry, and final persistence.
   - Confirm whether the failure is direct-mode routing, relay chunk size, accept-state mismatch, or receiver file persistence.
   - Include Oracle server limits in the audit: `MAX_RELAY_DATA`, per-peer queue cap, queued chunk behavior, and ACK handling.
   - Done when a large file transfer completes after accept and shows a precise error if it cannot.

8. Voice recording fix
   - Trace recorder permission, press/hold gesture state, recorder initialization, active recording flag, and audio file creation.
   - Fix the smallest broken UI/provider boundary.
   - Done when hold-to-record becomes active, records audio, stores metadata, and sends or reports a precise permission/device error.

9. Security validation
   - Capture traffic on the Oracle server and/or PC while sending a known test phrase.
   - Verify whether plaintext appears in server logs, packet payloads, or app logs.
   - Document visible metadata separately from message content exposure.
   - Done when we can state exactly what the server can see and provide capture evidence.

## Current Next Step

- Current shipped fixes:
  - `cc1f798` warmed active contacts in the background.
  - `1c0f5ef` tracked background contact warm connection.
  - `a31ed01` fixed passive chat connection status so bootstrap-online route warming does not look stuck.
  - `26c7952` fixed stale FFI peer ID reads by using isolate-local connection/presence callbacks.
  - Relay fallback now refreshes peer activity so a newly relayed route is not immediately timed out before key exchange can complete.
  - Parent repo `6b69a3e` fixed CyxChat relay peer liveness in `D:\Dev\conspiracy\tools\cyxchat-server.c`.
  - Server source of truth on this PC: `D:\Dev\conspiracy\tools\cyxchat-server.c`.
  - Deployed to Oracle on 2026-06-07.
  - Changed peer expiry from 5 seconds to 180 seconds.
  - Fixed scheduled queue delivery to scan all `MAX_PEERS` slots instead of only `g_peer_count`.
  - Refresh sender activity when a known peer sends a `CYXWIZ_UDP_RELAY_PKT`.
  - Added server-side sender recovery from relayed UDP data packets (`[0xF6][from_id:32]`) when the sender's source IP:port no longer matches the registration table.
  - Oracle service verified active on UDP `7777` after restart.
  - Oracle backups: `/home/ubuntu/cyxchat-server..bak` and `/home/ubuntu/cyxchat-server.c..bak`.
  - Second deployment backup: `/home/ubuntu/cyxchat-server.20260607055950.bak` and `/home/ubuntu/cyxchat-server.c.20260607055950.bak`.

- Next fix target:
  - Install/download the latest build, then validate live bidirectional messaging with Android devices A and B while tailing `/home/ubuntu/server.log`.
  - Confirm A -> B and B -> A each show send, relay/direct route, receive, persistence/display, and ACK.
  - If bidirectional text is stable, move next to Android notifications, then calls, large files, and recorder polish.

## Done Criteria For Each Fix

- Reproduced or strongly evidenced the failure.
- Made the smallest scoped change.
- Ran focused tests/analyzer/build checks for the touched area.
- Updated this tracker with the result.
- Committed and pushed only the relevant files.
