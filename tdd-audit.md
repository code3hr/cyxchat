# CyxChat TDD Stability Audit

This audit separates proven behavior from assumed behavior. A green app build does not make the chat server or message path stable; stability means the failure modes below are covered by automated tests or strict live checks.

## Current Stability Answer

The chat server is not yet proven production-stable.

Evidence:

- GitHub release CI validates Flutter analyzer/tests and cross-platform release builds.
- CI now runs the native C test suite before platform release builds.
- CI does not build or test `cyxchat-server`.
- The active server source of truth is currently outside this repo at `D:\Dev\conspiracy\tools\cyxchat-server.c`.
- Existing live P2P relay checks can report success when the server accepts a relay packet even if the receiver gets nothing.
- The active `0xF8` relay path forwards instantly with no ACK and only queues when the target is not registered.

## Backend Risks To Cover First

- Strict relay delivery: A registered peer A sends via server to registered peer B; B must receive the exact payload, otherwise the test fails.
- Offline queue delivery: A sends to offline B; when B registers, B must receive the queued payload exactly once.
- Online-but-not-receiving: if `sendto` fails or the receiver path is stale, the server should not count the message as delivered without retry/queue evidence.
- `0xE3` relay data path: define whether offline targets are queued or rejected. Current behavior drops the packet when target is missing.
- Queued message deletion: queue files are deleted after `sendto`, not after recipient confirmation.
- ACK code drift: pending-delivery and ACK helpers exist, but the main loop no longer processes pending delivery retries.
- Server CI gap: server build and relay contract tests are not part of release gating.

## Frontend Risks To Cover First

- Chat send path: sending should not block on repeated foreground key exchange when a known peer key exists.
- Contact key sync: learned peer public keys must persist and restore after app restart.
- File transfer: chunks must advance only after successful native send and must retry/report failure clearly.
- Notifications: foreground, background, and killed-app behavior need separate tests; local Dart notifications cannot guarantee killed-app delivery by themselves.
- Calls: tests cover lifecycle edges, but not full signaling/media setup or TURN fallback.
- Connection status UI: bootstrap online, peer route warming, and per-message delivery state must not collapse into one misleading "establishing connection" state.

## TDD Rules For The Next Fixes

- Start every bug fix with a failing test or a strict live-check script that currently fails.
- Fix the smallest layer that explains the failed test.
- Run focused tests before committing.
- Push only the files touched by that fix.
- Promote live-check scripts into CI when they become deterministic.

## Immediate Test Backlog

1. Make the existing P2P relay test fail if peer B receives nothing.
2. Add a strict server relay contract test that can run against a local or Oracle server.
3. Add native C CI for `lib/tests`. Done in `.github/workflows/release.yml`.
4. Add server CI once `cyxchat-server.c` is moved into this repo or checked out by workflow.
5. Add Flutter provider tests for contact key restore, chat route warming, file transfer failure, and call signaling failure.
