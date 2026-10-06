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

## Follow-up review of `dcb78abf`

| Finding | Decision | Change and evidence |
| --- | --- | --- |
| Native X is dropped while accepting | Accept | X and Escape express terminal intent. The notifier waits for the same call's control, then declines a failed accept or ends an accepted call. Tests cover success, failure and replacement. |
| An incoming decline arrives after activation | Accept | Accept/decline validate the current incoming phase at the notifier boundary; decline also rejects an already accepted pending snapshot. A test uses stale child and inline callbacks for the same active call ID. |
| Posted incoming notifications remain after the call | Accept | Serialize show/cancel with a call-specific ID. Tests cover acceptance, decline, remote end, delayed show and widget disposal. Windows cancellation remains limited by the existing plugin's requirement for MSIX package identity. |
| Rejected native fixture call_start panics | Accept | Return the bridge error in the worker's JSON response. A real peer test checks MissingConversation followed by a successful snapshot request. |

The spec review also found that closing replacement B could wait for accept A.
The wait now applies only when the control's call ID matches; a failing-then-passing
test checks that B's decline is sent before A completes.

## Follow-up review of `c897f3ea`

| Finding | Decision | Change and evidence |
| --- | --- | --- |
| Clicking the peer leaves the main window minimized | Accept | Restore the main window before show/focus. A widget test uses the application router and a minimized native-window fixture. |
| A background DM read releases admission during call start | Accept | Keep admission while start is running and until a fresh successful confirmation. A controlled test checks a late pre-start read and failed confirmation. |
| Windows voice UI test storage is never removed | Accept | The Node runner owns the temporary directory and deletes it after the desktop process exits, when Rust storage handles have closed. Cleanup retries transient Windows handle errors. |
| Restore loses a click when pending window startup fails | Accept | Wait for pending startup, recheck the desired call and retry once if no window exists. A controlled startup-failure test verifies the new attempt. |
| Automatic setup failure races manual hang-up | Accept | Serialize controls per call ID. Manual and automatic end share the wait/recheck path, preserving audio errors. Tests check one end during concurrent close and during a held accept. |
| Native test probe retains its CPAL player after app hang-up | Accept | Reconcile the probe against its originating session before each public peer command. The real scenario starts probe audio, hangs up in the app and checks that the probe is released. Reset commands match both session and call IDs. |

The final spec and standards reviews also reproduced setup failure while accept
was still pending. Both terminal paths now wait for that call's control gate;
the regression changed from zero ends to exactly one `setup_failed` end after
accept completes. Replacement calls retain independent gates.

## Follow-up review of `e243c3db`

| Finding | Decision | Change and evidence |
| --- | --- | --- |
| Test teardown mutates its listener collection during iteration | Do not accept | The pinned window_manager 0.5.2 getter returns `List<WindowListener>.from(_listeners)`. Teardown iterates this snapshot while removing internal listeners. The unchanged widget test and the complete Flutter CI job pass. |
| Other sessions cannot replace the selected call | Do not accept | Retaining the originating session preserves the agreed single audio owner. Once its call disappears, selection promotes another session that still has a call. Call waiting needs a separate product policy. |
| Invite setup or mounting failure skips native test cleanup | Accept | Register independent Flutter teardown callbacks immediately after acquiring Rust, the peer and the provider container. Their reverse order unmounts the view before disposing providers, the peer and Rust. Real invalid-invite fault injection before mounting left one peer directory before the fix and none after it. |
| Busy controls also block opening the original DM | Accept | Keep navigation and terminal intent available during control operations. One action policy is shared by the strip, host and child. Failing-then-passing tests check the peer click in all three paths while accept is held. |

## Follow-up review of `08fac9da`

| Finding | Decision | Change and evidence |
| --- | --- | --- |
| Native capture cleanup is counted before its real stop completes | Accept | Record successful capture/playback start and stop after the underlying operation completes. Four controlled tests cover pending, successful and failed stops for both backends. Native scenarios retain real Record/CPAL defaults. |

## Follow-up review of `683c4cb7`

| Finding | Decision | Change and evidence |
| --- | --- | --- |
| A stalled capture stop delays playback release | Accept | Cancellation starts independent teardown for acquired handles. `stop` joins that work; the serialized audio owner still waits for startup and all teardown before replacement. Two failing-then-passing lifetime tests check stalled active and late capture teardown. |
| Failed accept permanently suppresses a cancelled notification | Accept | Reset the notification attempt while busy and start a new attempt when the incoming call becomes retryable. A generation rejects old readiness/focus/show work even for the same call ID. Tests cover an already posted alert and pending initialization. |
| The setup-control test has an unused incoming-call import | Do not accept | The test uses `kCallDeclineReasonHangup`, declared in that file. Analyze is clean; deleting the import would remove the constant's direct declaration from scope. |
