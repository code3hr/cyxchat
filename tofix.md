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
- [x] Native message ID persistence: direct text native IDs are stored with messages and restored on chat service connect for ACK/read/edit/delete/reply mapping.
- [x] Call signaling hardening: early remote ICE candidates are buffered until remote SDP is ready, and stale call signals are ignored unless they match the active peer/state.
- [x] Verification baseline: use focused Dart analyzer checks on touched Dart files until app-scope analysis is stable.
- [x] Media cleanup: deleting direct messages/conversations removes referenced app-support media files and clears live file caches.
- [x] Non-text retry UI: media retry rows now show `Retrying...` while the replacement file/voice transfer is in progress.

## Next Fixes

1. Read receipts
   - Add retry/backoff if sending a read receipt fails while the peer is temporarily unreachable.

2. Native message ID persistence
   - Audit native ID persistence for direct media and group messages once their native ACK paths are surfaced.

3. Group message status
   - Surface native group ACK state in Dart.
   - Update outgoing group message delivery status from group ACK callbacks.

4. Group media and voice audit
   - Check whether group media has the same persistence/status/retry gaps as direct media.
   - Fix with shared helpers only if it reduces real duplication.

5. Production verification
   - Run app-level analyzer/build.
   - Run C tests where native protocol behavior changed.
   - Add focused Dart tests for message status and media metadata when test harness is stable.

## Verification Baseline

- Format touched Dart files with `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe format <files>`.
- Analyze touched Dart files with `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze <files>`.
- In the current sandbox, analyzer process spawning requires an elevated run; use the same command elevated when the sandbox reports `CreateFile failed 5`.
- Treat app-scope analysis as unresolved until the command below stops hanging/crashing.

## Known Verification Caveat

- `dart analyze` via `D:\Flutter\flutter\bin\dart.bat` hung in PowerShell.
- Direct `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe format ...` works.
- Direct `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze <file>` works for focused checks when elevated if sandbox process spawning is blocked.
- Direct `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .` from `app\` crashed with `FileSystemException: writeFrom failed` / `Bad state: The analysis server crashed unexpectedly`.
- `D:\Flutter\flutter\bin\flutter.bat analyze --no-pub` from `app\` hung and was interrupted.
