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
- [x] Read receipts retry: failed read receipts are deduplicated and retried with capped backoff while the app is running.
- [x] Native ID persistence audit: direct media remains file-transfer keyed because no chat ACK ID is surfaced; outgoing group file/image rows now persist the returned FFI `msgId` as the message ID.
- [x] Group message status: native group ACK tracking now emits delivered/failed events and outgoing group message rows update from those callbacks.
- [x] Group media/voice Dart path: group file sends now pass the native MIME argument, outgoing group media bytes are copied to app support storage, and group voice has service/provider persistence.
- [x] Native group media metadata transport: group file/image/voice sends now broadcast encrypted typed metadata to members, receivers validate/decrypt it through a media callback, and media metadata delivery participates in group ACK/retry tracking.
- [x] Incoming group media metadata persistence: Dart FFI now subscribes to native group media callbacks, provider exposes a media stream, and GroupService persists incoming media rows with payload status metadata.
- [x] Inline group media payload delivery: small group file/image/voice payloads are encrypted into the group media packet and forwarded through the existing incoming media persistence path.
- [x] Chunked group media payload delivery: larger group file/image/voice payloads are queued as encrypted group chunks from `cyxchat_group_poll`, assembled by receivers, and persisted by updating the pending media row when complete.
- [x] Group media missing-chunk recovery: receivers request stalled missing chunks with extended group file ACKs, and senders retain completed payloads briefly to answer targeted retransmission requests.
- [x] Group media transfer visibility: native group media progress/error callbacks are exposed through Dart FFI and GroupFFIProvider emits transfer progress/error stream events.
- [x] Group media transfer hardening tests: native tests cover chunk assembly, duplicate chunks, missing-chunk requests, and completion callback behavior.
- [x] Production verification baseline: native Debug build passes, native test suite passes, and Windows app CMake Debug build passes when run elevated outside sandbox restrictions.
- [x] Dart analyzer stabilization: app-wide `dart analyze .` completes elevated with exit 0 after SDK/analyzer baseline updates and warning cleanup.
- [x] Flutter test harness stabilization: `flutter.bat` remains unreliable in this shell, but direct elevated Flutter tools invocation runs the widget smoke test successfully.
- [x] Windows app build stabilization: direct elevated MSBuild of `runner\cyxchat.vcxproj` completes and produces `runner\Debug\cyxchat.exe`, avoiding the unreliable `flutter.bat` wrapper path.
- [x] Focused Dart coverage: service-level Flutter tests now cover persisted message status/media metadata round-trips, direct file transfer delivered/failed updates, emitted status updates, and direct unread-to-read handling.
- [x] Call/voice lifecycle coverage: Flutter tests cover incoming call reject/busy behavior, voice message metadata JSON escaping, and stable voice duration formatting; voice metadata now uses structured JSON encoding.
- [x] Voice playback temp cleanup: playback temp files are tracked and removed on stop, completion, failed load, and provider disposal.

## Next Fixes

1. Device-backed audio/video integration audit
   - Validate microphone/camera acquisition, active-recording disposal, and WebRTC connected/disconnected transitions on Windows.
   - Add narrow adapter seams for native/device APIs where tests cannot exercise behavior without real hardware.

## Verification Baseline

- Format touched Dart files with `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe format <files>`.
- Analyze touched Dart files with `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze <files>`.
- In the current sandbox, analyzer process spawning requires an elevated run; use the same command elevated when the sandbox reports `CreateFile failed 5`.
- Direct elevated app-scope analysis is the current analyzer baseline.

## Known Verification Caveat

- `dart analyze` via `D:\Flutter\flutter\bin\dart.bat` hung in PowerShell.
- Direct `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe format ...` works.
- Direct `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze <file>` works for focused checks when elevated if sandbox process spawning is blocked.
- Direct sandboxed `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .` from `app\` fails with `CreateFile failed 5` when spawning `analysis_server`.
- Direct elevated `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .` from `app\` still hung past a bounded 120 second verification run on 2026-06-06.
- Direct elevated `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .` from `app\` passed with exit 0 on 2026-06-06 after analyzer baseline updates.
- Direct elevated `C:\Program Files\CMake\bin\cmake.exe --build D:\Dev\conspiracy\cyxchat\app\build\windows\x64 --config Debug` passed on 2026-06-06.
- Direct elevated `C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\amd64\MSBuild.exe D:\Dev\conspiracy\cyxchat\app\build\windows\x64\runner\cyxchat.vcxproj /p:Configuration=Debug /m:1 /v:m` passed on 2026-06-06.
- Direct elevated `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=D:\Flutter\flutter\packages\flutter_tools\.dart_tool\package_config.json D:\Flutter\flutter\bin\cache\flutter_tools.snapshot test --no-pub test\widget_test.dart` passed on 2026-06-06.
- `D:\Flutter\flutter\bin\flutter.bat --version` and `flutter.bat test --help` timed out in this shell and spawned native build processes; use direct Flutter tools invocation instead.
- Direct `D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .` from `app\` crashed with `FileSystemException: writeFrom failed` / `Bad state: The analysis server crashed unexpectedly`.
- `D:\Flutter\flutter\bin\flutter.bat analyze --no-pub` from `app\` hung and was interrupted.
