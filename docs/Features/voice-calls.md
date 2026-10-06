# Voice calls

Desktop calls have an independent native window for incoming, outgoing and active
phases. A compact strip below the main view provides the same controls and a
button to restore the window. Clicking the peer in either view opens the original
DM. Messages, attachments, search and scrolling remain available during a call.
Navigation to another DM, group, channel or Settings keeps the audio running.
Opening the originating DM remains available while call controls are pending.

- Minimize preserves the call. The restore button brings its window forward.
- Close or Escape declines an incoming call, cancels an outgoing call or hangs up
  an active call. Remote termination closes the window and removes the strip.
  Closing during acceptance waits for that same call's control operation, then
  declines on failure or ends the accepted call. Replacement calls do not wait
  for an older call's control.
  Automatic setup-failure completion uses the same serialized terminal path.
- The microphone button becomes available after capture and playback start.
  Muting suppresses outgoing frames. A setup error retains hang-up controls when
  signaling also fails.
- Incoming calls time out after 30 seconds. Answer, decline, cancel and end stop
  the ringtone immediately. Failed controls remain retryable.
- The supplied `29_cipher_stream` recording plays through the selected CPAL output
  device. See [recording provenance](../../assets/audio/README.md).

## Runtime ownership

`VoiceCallHost` sits above every route and reads the full DM list. The selected
session remains the call's origin until its snapshot no longer contains a call.
Route snapshots cannot override this owner with older cached call data.
Another session cannot replace a call that still exists. Once it ends, selection
promotes another session that still contains a call; there is no call-waiting UI.

One shared audio orchestrator serializes replacement. Cancellation stops frame
work immediately; startup and teardown must finish before another capture or
player opens. Delayed controls, setup failures and drain responses are tied to
their call ID and cannot affect a replacement call.

Every desktop starts the same executable with `--mosh-call-window` in a separate
process. `MOSH_CALL_WINDOW=1` also identifies child startup on hosts that omit Dart
entrypoint arguments. GTK/EGL ownership stays independent on Linux. Stdio carries
only display metadata and commands with session and call IDs, without a listening
port. The child initializes no Rust runtime, database or audio owner. The parent
validates commands against the current call, waits for child exit on closure and
terminates an unresponsive child. A window failure leaves the main strip usable;
its restore button recreates the window. No additional window plugin is required.
Android and iOS use the strip inside system safe insets.

On Windows, the environment marker bypasses app_links' duplicate-instance handoff.
The child uses the separate `MOSH_CALL_WINDOW` Win32 class, so new `mosh://` links
still target the main application's `FLUTTER_RUNNER_WIN32_WINDOW` class.

Incoming notifications await initialization and recheck the current incoming call
before posting. A completed initialization cannot notify about an ended call.
Notifications are suppressed while either the main window or call window is focused.
Showing and cancelling are serialized; acceptance, decline, remote end and widget
disposal remove the call's notification even if its show operation finishes late.
The existing notification plugin cannot cancel Windows alerts without MSIX
package identity; the current installer does not supply that identity. Other
platforms use the plugin's cancellation support. See its
[Windows limitations](https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications_windows/README.md#limitations).

## Checks

Widget tests use the existing scriptable gateway and bridge plus observable audio
factories under `test/support/`. They cover messaging, navigation, call-ID binding,
late accept, remote termination, audio replacement, setup failure, timeout and
window startup after termination.

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
functions remain within the limit.

## Verification on Linux, 2026-10-06

- Full native voice scenario passed with the default OpenGL renderer, including
  bidirectional encrypted audio, messaging, all route kinds, repeated calls,
  OS close in all phases and minimize/restore. Audio used real record/CPAL streams
  connected to PulseAudio's sine source and null output rather than physical
  microphone/speaker hardware.
- 174 focused Flutter tests passed, covering system insets, delayed notification
  readiness, focused-window suppression and forced process termination with a
  broken input pipe, plus accept/close races, notification cancellation,
  admission confirmation, main-window restore, setup/control serialization and
  failed window-start retry. Analyze and format passed.
- Full Flutter suite: 1509 passed, four skipped. One unchanged test,
  `media_kit_tracer_test.dart`, also fails when run alone because headless libmpv
  returns no screenshot. It imports no voice-call implementation.
- Rust runtime unit/integration tests passed; doc tests, fmt and clippy passed.
  All seven ringtone tests passed, including explicit selected-output stream
  start/stop/repeat on PulseAudio.
- Changed lines represented in LCOV: Dart 95.2% (818/859), Rust 97.7% (126/129).
  Application entrypoints are additionally exercised by the native scenario. Ringtone source
  coverage is 100% for recording conversion and 96.9% for CPAL playback. The
  available LCOV output contains no branch counters. Linux process startup and
  desktop window behavior are additionally exercised by the native scenario.
- Windows/macOS child process behavior has not been executed locally on those
  hosts. Headless CPAL occasionally logs an xrun while streams close;
  the scenario still verifies audio progress and resource release.

The CodeAnt findings and decisions are recorded in
[the IVO-23 review notes](../Proposals/ivo-23-codeant-review.md).
