# IVO-23: CodeAnt review decisions

PR: [#59](https://github.com/redstone-md/mosh-flutter/pull/59).
Initial review examined `52d85b193815bbb05d24862c7d6d48464218c04d`.

| Finding | Decision | Change and evidence |
| --- | --- | --- |
| An unresponsive plugin window can remain orphaned | Accept | Use one owned child process on every desktop. Wait for exit, then escalate TERM to KILL. Four process tests cover normal close, refused close, ignored termination and broken stdin after exit. The real Linux scenario checks OS close in every phase. |
| Compact controls ignore phone system insets | Accept | Wrap the strip in `SafeArea(top: false)`. A widget test checks bottom and lateral insets. |
| Failed coordinator close can retain a child | Accept | Process cleanup owns termination and independently releases both transport handles. Exit failures still propagate. |
| Notification initialization can drop an incoming call | Accept | Await readiness, then recheck phase and call ID. Tests cover delayed readiness and a call that ends during initialization. |
| A focused Linux call window still gets a notification | Accept | Query both main and child focus on all desktops. A test covers child focus; the coordinator rejects results from replaced windows. |
| A stale native fixture command resets the live probe sequence | Accept | Reset only after successful matching decline/end. The real peer scenario checks that stale end preserves increasing media sequence numbers. |
| Ringtone test name claims a decline failure it does not simulate | Accept | Rename it to describe the unchanged pending snapshot it actually tests. |
| Stdio requires an explicit flush per RPC | Do not accept | Dart 3.12.2 immediately forwards IOSink events to its socket stream consumer; awaiting a reply gives that consumer execution time. Repeated real-process calls pass without explicit flush. Concurrent flush can bind the sink and reject another write. |

The flush decision was checked against the installed Dart SDK's
`lib/io/io_sink.dart` and `_internal/vm/bin/socket_patch.dart`, not inferred from a
mock transport. Its review thread remains open because the proposed change is
not appropriate for this transport.

The unified process adapter also removes `desktop_multi_window` and its native
runner callbacks. On Windows, the child marker bypasses app_links' existing-instance
handoff and selects a distinct Win32 class; deep links continue to target the main
window. The Windows native fixture runs both classes in CI.

Verification details, commands and platform limitations are in
[voice calls](../Features/voice-calls.md).
