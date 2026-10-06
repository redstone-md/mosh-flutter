# Voice calls

Desktop calls have an independent native window for incoming, outgoing and active
phases. A compact strip below the main view provides the same controls and a
button to restore the window. Clicking the peer in either view opens the original
DM. Messages, attachments, search and scrolling remain available during a call.
Navigation to another DM, group, channel or Settings keeps the audio running.

- Minimize preserves the call. The restore button brings its window forward.
- Close or Escape declines an incoming call, cancels an outgoing call or hangs up
  an active call. Remote termination closes the window and removes the strip.
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

One shared audio orchestrator serializes replacement. Cancellation stops frame
work immediately; startup and teardown must finish before another capture or
player opens. Delayed controls, setup failures and drain responses are tied to
their call ID and cannot affect a replacement call.

Windows and macOS use a `desktop_multi_window` child engine. Linux starts the
same executable with `--mosh-call-window` in a separate process, keeping GTK/EGL
ownership independent. The same presentation view receives only display metadata
and returns commands containing both session and call IDs. Linux exchanges these
messages over inherited stdio, without a listening port. Neither child initializes
the Rust runtime, database or audio owner. The main process validates commands
against the current call. Window startup or renderer failure leaves the main strip
usable; its restore button recreates the window. Android and iOS use the strip
without a native child window.

## Checks

Widget tests use the existing scriptable gateway and bridge plus observable audio
factories under `test/support/`. They cover messaging, navigation, call-ID binding,
late accept, remote termination, audio replacement, setup failure, timeout and
window startup after termination.

The native UI test uses a real independent installation process, Moss discovery,
AES-GCM, Opus, `record` capture and CPAL playback. It covers decline, cancel,
incoming acceptance, bidirectional audio, navigation, message delivery, mute,
remote end and a repeated call.

Prepare Moss, compile the native peer fixture, then run on a desktop with usable
input/output devices:

```sh
node scripts/moss-prepare.mjs
cargo test --manifest-path mosh-core/Cargo.toml --test device_link_flow --no-run
node scripts/moss-test.mjs --voice-ui
```

`flutter drive --debug --no-start-paused` builds this integration target and starts
its main entrypoint directly in each engine or process. `flutter test` inserts a suite launcher that
leaves child engines waiting for a separate test connection. Linux builds also
need the project's existing plugin prerequisites, including libcurl, libmpv and
a JDK with JNI headers. Headless Linux can use PulseAudio's null sink and sine
source, Xvfb and Openbox. With `MOSH_TEST_WINDOW_ACTIONS=1`, the scenario additionally
uses `xdotool` and `xprop` to check OS close in all phases and audio while minimized.
The normal scenario does not require those window-manager tools.

Behavioral test bodies may exceed the 50-line function limit to keep their setup,
actions and assertions together. The native peer's command dispatcher retains
the same exception so its public-action routing stays in one place. Production
functions remain within the limit.

## Verification on Linux, 2026-10-06

- Full native voice scenario passed with the default OpenGL renderer, including
  bidirectional encrypted audio, messaging, all route kinds, repeated calls,
  OS close in all phases and minimize/restore. Audio used real record/CPAL streams
  connected to PulseAudio's sine source and null output rather than physical
  microphone/speaker hardware.
- Final focused Flutter suite: 142 tests passed. Analyze and format passed.
- Full Flutter suite: 1483 passed, four skipped. One unchanged test,
  `media_kit_tracer_test.dart`, also fails when run alone because headless libmpv
  returns no screenshot. It imports no voice-call implementation.
- Rust runtime unit/integration tests passed; doc tests, fmt and clippy passed.
  All seven ringtone tests passed, including explicit selected-output stream
  start/stop/repeat on PulseAudio.
- Changed executable-line coverage exceeds 80% in Dart and Rust. Ringtone source
  coverage is 100% for recording conversion and 96.9% for CPAL playback. The
  available LCOV output contains no branch counters. Linux process startup and
  desktop window behavior are additionally exercised by the native scenario.
- Windows/macOS runner registration and plugin transport have not been executed
  on those hosts. Headless CPAL occasionally logs an xrun while streams close;
  the scenario still verifies audio progress and resource release.
