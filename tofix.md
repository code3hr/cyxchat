# CyxChat Production Fix Tracker

This file tracks the core chat-app readiness work. Keep each fix small, auditable, tested where practical, committed, and pushed before moving to the next fix.

## Working Rule

- Audit the target path before editing.
- Implement the smallest production-impacting fix.
- Format and run focused checks.
- Commit and push after each completed fix.
- Do not mix unrelated dirty worktree changes into a fix commit.

## Done

- [x] Direct chat media status: voice/audio/file messages now stay in the transfer-backed path instead of being treated like failed text.
- [x] Direct chat media lifecycle hooks: FileProvider exposes transfer completion/error callbacks and ChatService can update related message status.
- [x] Direct chat metadata safety: file/audio metadata is JSON-encoded instead of hand-built strings.
- [x] Direct chat duplicate handling: removed content-hash dedup that could suppress legitimate repeated messages.
- [x] Direct chat live updates: ACK/edit/delete DB updates now emit changed messages to the UI stream.
- [x] Network bootstrap: FileProvider transfer completion/error callbacks are wired to ChatService status updates.
- [x] Calls: outgoing unanswered calls timeout with `noAnswer`.
- [x] Calls: incoming unanswered calls expire.
- [x] Calls: permission-denied accept path rejects the caller instead of leaving them waiting.
- [x] Media persistence: sent/received file and voice bytes are stored in app support storage, message metadata saves `localPath`, and playback/save can recover after restart.
- [x] Non-text retry: failed file/voice messages retry from persisted local media, start a replacement transfer, and update the existing message with the new transfer ID.
- [x] Read receipts: marking a direct conversation read sends privacy-aware read receipts for unread inbound messages with known native IDs.

## Next Fixes

1. Verification baseline
   - Get a reliable `flutter analyze` or `dart analyze` path.
   - Add a repeatable command note once the working command is found.

2. Media persistence
   - Add a cleanup policy for orphaned app-support media files after message/conversation deletion.

3. Non-text retry
   - Consider a clearer UI label for media retries while the replacement transfer is still in progress.

4. Read receipts
   - Persist inbound native IDs so read receipts still work after app restart.

5. Native message ID persistence
   - Persist native message IDs with local messages.
   - Restore ACK/edit/delete/reply mapping after app restart.

6. Call signaling hardening
   - Buffer early ICE candidates until the peer connection and remote description are ready.
   - Add call state validation for stale signals after timeout/end.

7. Group message status
   - Surface native group ACK state in Dart.
   - Update outgoing group message delivery status from group ACK callbacks.

8. Group media and voice audit
   - Check whether group media has the same persistence/status/retry gaps as direct media.
   - Fix with shared helpers only if it reduces real duplication.

9. Production verification
   - Run app-level analyzer/build.
   - Run C tests where native protocol behavior changed.
   - Add focused Dart tests for message status and media metadata when test harness is stable.

## Known Verification Caveat

- `dart analyze` via `D:\Flutter\flutter\bin\dart.bat` hung in PowerShell.
- Direct `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe format ...` works.
- Direct analyzer was blocked once by sandbox process-spawn permissions, then timed out when elevated.
