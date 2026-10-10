# Calls

Desktop calls have an independent native window for incoming, outgoing and active
phases. A compact strip below the main view shows status and a button to restore
the ready window. It supplies call controls while the window is unavailable.
Clicking the peer in either view opens the original
DM. Messages, attachments, search and scrolling remain available during a call.
Navigation to another DM, group, channel or Settings keeps the audio running.
Opening the originating DM remains available while call controls are pending.

- Minimize preserves the call. The restore button brings its window forward.
- Close or Escape in the call window declines an incoming call, cancels an
  outgoing call or hangs up
  an active call. Remote termination closes the window and removes the strip.
  Closing during acceptance waits for that same call's control operation, then
  declines on failure or ends the accepted call. Replacement calls do not wait
  for an older call's control.
  Automatic setup-failure completion uses the same serialized terminal path.
  The main window retains its navigation and dialog Escape shortcuts.
- The microphone button becomes available after capture and playback start.
  Muting suppresses outgoing frames. A setup error retains hang-up controls when
  signaling also fails.
- Incoming calls time out after 30 seconds. Answer, decline, cancel and end stop
  the ringtone immediately. Failed controls remain retryable.
- The supplied `29_cipher_stream` recording plays through the selected CPAL output
  device. See [recording provenance](../../assets/audio/README.md).

## Selected-device coordination (#46)

Call offer, answer, selection, occupancy and terminal controls travel inside MLS
application messages. The receiver checks the actual MLS leaf signer, conversation,
and current admitted device's Moss identity. Plaintext accept/end envelopes are
removed; participating clients upgrade together.

Answering requests selection. The receiving installation remains pending, displays
“Waiting for confirmation…”, and sends no voice media until the caller selects it.
All reachable linked receivers ring; the caller accepts the first answer or refusal.
A later refusal from another receiver cannot end the selected pair. The other
receivers stop ringing, retain account occupancy, and cannot start an unrelated call.

Simultaneous outgoing calls choose the smaller authenticated caller-signer/call-ID
pair before media starts. Only an authenticated concurrent offer establishes the
superseded ID. A cancel from the window still displaying that ID ends the merged
call. Failed subscription leaves the existing call intact.

Occupancy uses 15-second leases with two-second heartbeats. Known pending/active
calls block new admission across DMs, including occupancy in the same DM. A healed
partition can reveal several calls: snapshots report a conflict, existing calls
continue, an amber notice explains it, and new calls stay blocked until it resolves.
This remains best effort while installations cannot reach each other.

The encrypted session record retains per-leaf control sequence numbers and the last
512 closed IDs. Local presentation dismissal is distinct from confirmed termination:
a device that declined must still observe another device's accepted call. Authorized
terminal controls remain valid after a newer unrelated offer; old occupancy cannot
overwrite newer occupancy. Terminal delivery retries every two seconds for 15 seconds
using a bounded queue of 32 controls. A local end saves its book before returning.

Desktop calls now use the [native audio/video owner](native-call-media.md), with
selected-only ephemeral key agreement, independent capture and bounded decoded
presentation. Android/iOS retain their separate voice path.

## Runtime ownership

`VoiceCallHost` sits above every route and reads the full DM list. The selected
session remains the call's origin until its snapshot no longer contains a call.
Route snapshots cannot override this owner with older cached call data.
Another session cannot replace a call that still exists. Once it ends, selection
promotes another session that still contains a call; there is no call-waiting UI.
When there is no retained owner, selection prefers an already active call over
pending or outgoing calls, irrespective of the DM list order.

The legacy mobile/baseline voice path uses one shared audio orchestrator to
serialize replacement. Cancellation stops frame
work immediately; startup and teardown must finish before another capture or
player opens. Delayed controls, setup failures and drain responses are tied to
their session and call IDs and cannot affect a replacement call.
Starting a call refreshes the DM list before admission; a failed fresh read
blocks the start even if an older cached list contained no calls.
Cancellation starts capture and playback teardown independently, so waiting for
one handle cannot delay release of the other. Replacement still waits for both.

Every desktop starts the same executable with `--mosh-call-window` in a separate
process. `MOSH_CALL_WINDOW=1` also identifies child startup on hosts that omit Dart
entrypoint arguments. GTK/EGL ownership stays independent on Linux. Stdio carries
display metadata, commands and frame acknowledgements with session and call IDs.
The child initializes no Rust runtime, database or audio owner. The parent
validates commands against the current call, waits for child exit on closure and
terminates an unresponsive child. Once the child has accepted its first call
presentation, the main strip keeps only status and the restore button. Call
controls stay in that window. Startup or presentation failure restores the
strip's controls, and its restore button recreates the window. No additional
window plugin is required.
Android and iOS use the strip inside system safe insets. While a call is shown,
the host consumes the keyboard inset for both the route and strip, removing it
from the nested Scaffold so the composer does not reserve the inset twice.
The wrapper stays mounted across call admission and termination to retain drafts.

### Decoded video presentation (#46)

The production native engine copies decoded RGBA into a latest-frame slot with one spare
conversion buffer, each capped at 1920×1080×4 bytes. Failed conversion preserves
the last complete frame. The host owns its copied pixels; native frame pointers
never enter Flutter. Frame metadata and pixels travel as bounded binary packets.

Presentation uses a dedicated loopback stream so bulk pixels cannot delay stdio
controls. The parent passes a random 256-bit, one-time capability to the spawned
child through inherited stdio. The listener accepts at most four unauthenticated
connections, each for two seconds, and admits one renderer. No user-facing port
setting or additional server is involved. This stream carries decoded display
pixels only; peer media still travels through Moss.

The parent admits one frame until the child acknowledges its exact session, call,
sequence and local/remote lane. A stalled renderer receives no further frames and
is terminated after five seconds. Restore creates a new renderer and capability.
Rendering holds one image per lane and one decode in flight. Source/transfer age
and monotonic decode duration count toward a one-second display budget; stale
frames are discarded. Every image, codec and immutable buffer has explicit cleanup.

The video stage fits narrow windows, preserves image aspect ratio, mirrors local
preview, and fades only its presence for 150 ms. Pixel updates do not animate;
reduced motion removes the fade. The compact controls remain usable independently.
The stage is wired to the window's frame sink; the application media adapter and
camera owner are being implemented in the next stage.

On Linux x64 debug, a real separate renderer admitted 88/90 synthetic 720p frames
before a forced renderer crash and 81/90 after restoration. Frame round-trip
median/p95 was 17/30 ms over 169 samples. Before separating bulk pixels from stdio,
it was 155/187 ms over 17 samples; body transfer, rather than copying or decoding,
dominated. These are short, same-host renderer checks, not sustained camera or
audio/video quality acceptance. The isolated Moss check additionally copied actual
decoded native frames and rejected all media in the tampered-key direction.

Run the real desktop presentation check after preparing Moss:

```sh
flutter drive --target integration_test/call_video_window_test.dart --driver test_driver/integration.dart -d linux --debug --no-start-paused
```

Use `windows` or `macos` for the corresponding desktop host. Set
`MOSH_CALL_FRAME_PROFILE=1` only when collecting timing diagnostics.

On Windows, the environment marker bypasses app_links' duplicate-instance handoff.
The child uses the separate `MOSH_CALL_WINDOW` Win32 class, so new `mosh://` links
still target the main application's `FLUTTER_RUNNER_WIN32_WINDOW` class.

Incoming notifications await initialization and recheck the current incoming call
before posting. A completed initialization cannot notify about an ended call.
Notifications are suppressed while either the main window or call window is focused.
Each focus probe handles failure independently; an unavailable probe cannot
prevent an alert, while a positive result from the other window still suppresses it.
While suppressed, a one-second retry rechecks both windows so an unanswered call
can notify after focus moves away, without requiring a new session snapshot.
The retry stops on acceptance, termination or widget disposal.
Showing and cancelling are serialized; acceptance, decline, remote end and widget
disposal remove the call's notification even if its show operation finishes late.
Failed acceptance allows a fresh alert while the call remains incoming. An attempt
generation rejects old notification work that resumes after that retry.
The existing notification plugin cannot cancel Windows alerts without MSIX
package identity; the current installer does not supply that identity. Other
platforms use the plugin's cancellation support. See its
[Windows limitations](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications_windows/README.md#limitations).

## Checks

Widget tests use the existing scriptable gateway and bridge plus observable audio
factories under `test/support/`. They cover messaging, navigation, call-ID binding,
late accept, remote termination, audio replacement, setup failure, timeout and
window startup after termination.
Terminal buttons remain available during acceptance and wait for that call's
control operation. Bringing either desktop window forward restores it only when
minimized, preserving an already maximized window's geometry.

The native UI test uses a real independent installation process, Moss discovery,
AES-GCM, Opus, `record` capture and CPAL playback. It covers decline, cancel,
incoming acceptance, bidirectional audio, navigation, message delivery, mute,
remote end and a repeated call.
The peer probe releases its audio when its originating session no longer contains
the call. Stale controls from another session cannot reset its media sequence.

Prepare Moss, compile the native peer fixture, then run on a desktop with usable
input/output devices:

```sh
node scripts/moss-prepare.mjs
cargo test --manifest-path mosh-core/Cargo.toml --test device_link_flow --no-run
node scripts/moss-test.mjs --voice-ui
```

The Node runner creates the test data directory and passes it through
`MOSH_CALL_UI_TEST_DATA_DIR`. It removes the directory after the desktop process
exits, so Windows database handles cannot prevent normal cleanup. Run this
scenario through the runner rather than invoking its Flutter target directly.
Acquired native test resources register teardown immediately, so setup failure
before widget mounting also releases the peer and Rust bridge.

`flutter drive --debug --no-start-paused` builds this integration target and starts
its main entrypoint directly in each engine or process. `flutter test` inserts a suite launcher that
leaves child engines waiting for a separate test connection. Linux builds also
need the project's existing plugin prerequisites, including libcurl, libmpv and
a JDK with JNI headers. Headless Linux can use PulseAudio's null sink and sine
source, Xvfb and Openbox. With `MOSH_TEST_WINDOW_ACTIONS=1`, the scenario additionally
uses `xdotool` and `xprop` to check OS close in all phases and audio while minimized.
The normal scenario does not require those window-manager tools.

Behavioral test bodies and end-to-end scenario methods may exceed the 50-line
function limit to keep their setup, actions and assertions together.
The native peer's command dispatcher retains
the same exception so its public-action routing stays in one place. Production
functions remain within the limit. `VoiceCallOrchestratorNotifier` has a temporary
215-line type allowance: it owns the existing audio lifecycle and serialized
controls during the native-engine migration. Keeping those together preserves
the single call owner; the replacement adapter will remove the old audio setup.

## Verification on Linux, 2026-10-06

- Full native voice scenario passed with the default OpenGL renderer, including
  bidirectional encrypted audio, messaging, all route kinds, repeated calls,
  OS close in all phases and minimize/restore. Audio used real record/CPAL streams
  connected to PulseAudio's sine source and null output rather than physical
  microphone/speaker hardware.
- 199 focused Flutter tests passed, covering system insets, delayed notification
  readiness, focused-window suppression and forced process termination with a
  broken input pipe, plus accept/close races, notification cancellation,
  admission confirmation, main-window restore, setup/control serialization and
  failed window-start retry, terminal buttons during acceptance and alerts after
  either window loses focus. Analyze and format passed.
- Full Flutter suite: 1539 passed, four skipped. One unchanged test,
  `media_kit_tracer_test.dart`, also fails when run alone because headless libmpv
  returns no screenshot. It imports no voice-call implementation.
- Rust runtime unit/integration tests passed; doc tests, fmt and clippy passed.
  All seven ringtone tests passed, including explicit selected-output stream
  start/stop/repeat on PulseAudio.
- Changed lines represented in LCOV: Dart 95.5% (855/895), Rust 97.7% (126/129).
  Application entrypoints are additionally exercised by the native scenario. Ringtone source
  coverage is 100% for recording conversion and 96.9% for CPAL playback. The
  available LCOV output contains no branch counters. Linux process startup and
  desktop window behavior are additionally exercised by the native scenario.
- Windows/macOS child process behavior has not been executed locally on those
  hosts. Headless CPAL occasionally logs an xrun while streams close;
  the scenario still verifies audio progress and resource release.
  One run alongside the full Flutter suite reported ALSA I/O errors and timed out
  waiting for ringtone teardown. The unchanged scenario passed when rerun alone.

The CodeAnt findings and decisions are recorded in
[the IVO-23 review notes](../Proposals/ivo-23-codeant-review.md).

Verification for selected-device coordination: the full Flutter suite passed
1808 tests (four skipped); the final focused suite passed 196 tests after alias
and timeout fixes. The core full suite passed, and its final DM-focused run
passed 165 tests (13 helpers ignored), including real signed controls and
reordered occupancy. Flutter changed lines/branches measured 96.6%/94.4%;
Rust changed-line coverage measured 90.9% (stable LLVM emitted no branches).
Analyze, clippy and bridge regeneration passed. The native audio/video pipeline
is the next stage; these checks do not establish physical-camera acceptance.
