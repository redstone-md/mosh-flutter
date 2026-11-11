# Calls

On desktop a call shows in the main window, as on Android: an expanded view that
covers the content and can go full screen, and a mini view while the user
browses chats ([ADR 0052](../ADR/0052-desktop-calls-in-the-main-window.md)).

A platform without the native call engine (iOS) shows a compact strip of call
controls below the app instead.

Clicking the peer in
either view opens the original DM. Messages, attachments, search and scrolling remain available during a call.
Navigation to another DM, group, channel or Settings keeps the audio running.
Opening the originating DM remains available while call controls are pending.

Android ARM64 uses the same native audio/video protocol as desktop, with an
in-app call view. The minimize button or Back hides the expanded controls without
ending the call. Voice uses a compact strip; video uses a draggable mini-window.
The mini-window accumulates every pointer movement between rendered frames and
stays within the available viewport.
Tap Restore to reopen controls. Both remain available across chat/settings routes.
Device dialogs receive Back first. Camera permission refusal preserves
voice and reception. Android selects a communication output and paired microphone
through AudioManager. See [native media](native-call-media.md) for packaging and
the native media acceptance boundary.

An active video call uses Android system Picture-in-Picture when the user leaves
Mosh (Home/app switch), if the device and its PiP settings allow it. Only the video
stage is shown in system PiP above the entire root Navigator. Chats, controls and
open dialogs stay mounted offstage at their original size. Returning
restores the previous in-app presentation. Closing system PiP ends that exact call;
a delayed close cannot terminate a replacement. This adds no draw-over-apps
permission or second audio/video engine. It does not implement incoming calls
when Mosh is stopped, or guarantee calls after dismissing/locking its Activity.

- Minimize and Escape in the expanded view keep the call in the mini view.
- The end button declines an incoming call, cancels an outgoing call or hangs
  up an active call. Remote termination removes the call view.
  Closing during acceptance waits for that same call's control operation, then
  declines on failure or ends the accepted call. Replacement calls do not wait
  for an older call's control.
  Automatic setup-failure completion uses the same serialized terminal path.
  The main window retains its navigation and dialog Escape shortcuts.
- The microphone button follows the engine's microphone state, and muting is
  the engine's microphone choice. A setup error retains hang-up controls when
  signaling also fails.
- Incoming calls time out after 30 seconds. Answer, decline, cancel and end stop
  the ringtone immediately. Failed controls remain retryable.
- Incoming and outgoing calls play separate recordings. Desktop uses the selected
  CPAL output; Android uses native ringtone/call audio attributes and audio focus,
  respecting silent/vibrate mode. See [recording provenance](../../assets/audio/README.md).

New call-history entries retain the authenticated caller's direction in existing
message metadata. Incoming missed calls and outgoing no-answer have separate labels; answered calls
show incoming/outgoing and duration. The existing call-event contract is unchanged.
Old incorrectly attributed rows lack reliable origin data and are not rewritten.

## Selected-device coordination (#46)

Call offer, answer, selection, occupancy and terminal controls travel inside MLS
application messages. The receiver checks the actual MLS leaf signer, conversation,
and current admitted device's Moss identity. Plaintext accept/end envelopes are
removed; participating clients upgrade together. The envelope names no sender in
the clear, so a device remembers the controls it published and skips Moss's echo of
one before decryption, which MLS would refuse for its own message (MOSH-89).

Answering requests selection. The receiving installation remains pending, displays
“Waiting for confirmation…”, and sends no voice media until the caller selects it.
All reachable linked receivers ring; the caller accepts the first answer or refusal.
A later refusal from another receiver cannot end the selected pair. The other
receivers stop ringing, retain account occupancy, and cannot start an unrelated call.

Simultaneous outgoing calls choose the smaller authenticated caller-signer/call-ID
pair before media starts. Only an authenticated concurrent offer establishes the
superseded ID. A cancel from a view still displaying that ID ends the merged
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

Desktop and Android calls use the [native audio/video owner](native-call-media.md),
with selected-only ephemeral key agreement, independent capture and bounded decoded
presentation. iOS retains the separate voice path.

## Runtime ownership

`VoiceCallHost` sits above every route and reads the full DM list. The selected
session remains the call's origin until its snapshot no longer contains a call.
Route snapshots cannot override this owner with older cached call data.
Another session cannot replace a call that still exists. Once it ends, selection
promotes another session that still contains a call; there is no call-waiting UI.
When there is no retained owner, selection prefers an already active call over
pending or outgoing calls, irrespective of the DM list order.

Delayed controls and setup failures are tied to their session and call IDs
and cannot affect a replacement call.
Starting a call refreshes the DM list before admission; a failed fresh read
blocks the start even if an older cached list contained no calls.

With a native call engine (desktop and Android) the host shows the call in the
main window and keeps no second process, window or engine for it. The call's
buttons act on the orchestrator of the displayed session, which checks every
action against the current call ID.
The mini view and the iOS strip stay inside system safe insets. While a call is shown,
the host consumes the keyboard inset for both the route and strip, removing it
from the nested Scaffold so the composer does not reserve the inset twice.
The wrapper stays mounted across call admission and termination to retain drafts.

### Decoded video presentation (#46)

The production native engine copies decoded RGBA into a latest-frame slot with one spare
conversion buffer, each capped at 1920×1080×4 bytes. Failed conversion preserves
the last complete frame. Native frame pointers never enter Dart.

On desktop Rust presents each frame straight into a Flutter texture of the
main window; see [main-window textures](native-call-media.md#main-window-textures).
Android polls the newest frame over the bridge and decodes it in Dart: one
image per lane and one decode in flight, with stale frames discarded. Every
image, codec and immutable buffer has explicit cleanup.

The video stage fits narrow windows, preserves image aspect ratio, mirrors local
preview, and fades only its presence for 150 ms. Pixel updates do not animate;
reduced motion removes the fade. The compact controls remain usable independently.

On Windows a second `mosh.exe` started by a `mosh://` link hands the link to
the running instance, which app_links finds by the runner's
`FLUTTER_RUNNER_WIN32_WINDOW` class.

Incoming notifications await initialization and recheck the current incoming call
before posting. A completed initialization cannot notify about an ended call.
Desktop notifications are suppressed while the main window is focused. An
unavailable focus probe cannot prevent an alert.
While suppressed, a one-second retry rechecks the window so an unanswered call
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

Widget tests use the existing scriptable gateway and bridge under `test/support/`,
with a real `NativeCallOwner` over the bridge's scripted native calls where media
matters. They cover messaging, navigation, call-ID binding, late accept, remote
termination, media rebinding, setup failure and timeout.
Terminal buttons remain available during acceptance and wait for that call's
control operation. Bringing the desktop window forward restores it only when
minimized, preserving an already maximized window's geometry.

The native call UI test (`node scripts/moss-test.mjs --native-call-ui`, see
[native call media](native-call-media.md#build-and-checks)) runs a real
independent installation process with Moss discovery and the call engine.

The Node runner creates the test data directory and passes it through
`MOSH_CALL_UI_TEST_DATA_DIR`. It removes the directory after the desktop process
exits, so Windows database handles cannot prevent normal cleanup. Run this
scenario through the runner rather than invoking its Flutter target directly.
Acquired native test resources register teardown immediately, so setup failure
before widget mounting also releases the peer and Rust bridge.

The runner starts the scenario with `flutter drive --debug --no-start-paused`.
Linux builds also
need the project's existing plugin prerequisites, including libcurl, libmpv and
a JDK with JNI headers. Headless Linux can use PulseAudio's null sink and sine
source, Xvfb and Openbox.

Behavioral test bodies and end-to-end scenario methods may exceed the 50-line
function limit to keep their setup, actions and assertions together.
The native peer's command dispatcher retains
the same exception so its public-action routing stays in one place. Production
functions remain within the limit. `VoiceCallOrchestratorNotifier` keeps a
210-line type allowance: it owns the call dialog, the native media binding and
the serialized controls, and splitting them would break the single call owner.

## Tests removed with the call window (MOSH-101)

The call window process, its pipe, frame socket and coordinator are gone, so
the tests of that code went with it. What a user can still observe is covered
by the retained tests named here.

| Removed | Covered | Retained coverage |
|---------|---------|-------------------|
| `test/features/voice_call/call_window_app_test.dart` | the child window's view, title and close button | `test/features/voice_call/native_call_view_test.dart` and `call_video_stage_test.dart` for the shared view at minimum size; `main_window_call_host_test.dart` for the call in the main window |
| `test/features/voice_call/call_window_controls_test.dart` | which of the window and the strip shows the controls | `call_control_races_test.dart` for the strip; `main_window_call_host_test.dart` for the main window |
| `test/features/voice_call/call_window_coordinator_test.dart` and `voice_call_navigation_test.dart`: "window startup after a call ended never presents obsolete controls" | window start, restore and failure ordering | none: the behaviour no longer exists |
| `test/features/voice_call/call_window_pipe_test.dart`, `call_window_frame_channel_test.dart`, `call_window_frames_cases.dart` with its runner `voice_protocol_test.dart`, and `process_call_window_test.dart` | the stdio protocol, the frame socket and the child process lifetime | none for the transport; `test/state/native_call_owner_surfaces_test.dart` still covers the video surfaces reaching the owner |
| `test/features/voice_call/call_control_races_test.dart`: the "native close" variants and the commands sent through the window | a window command racing a pending accept | the same file, through the real buttons |
| `test/features/voice_call/call_notification_focus_cases.dart`: the "call" and "call failure" variants | the call window's focus suppressing an alert | the same file, for the main window |
| `test/features/voice_call/native_call_view_test.dart`: "child metadata preserves real flags and contains no media credentials" | the view state's pipe encoding | none: the encoding is deleted |
| `integration_test/native_call_test.dart` and `integration_test/call_video_window_test.dart` | a real call and synthetic frames through the window process | `integration_test/native_call_main_window_test.dart` for the call itself. The polled frame path that Android keeps has no real-engine test until MOSH-102 replaces it; `test/features/voice_call/native_call_session_test.dart` covers the poll against the scripted bridge |
| `test/support/call_window_platform.dart` and `test/support/call_window_process.dart` | fakes for the tests above | none needed |
| `windows/runner/tests/window_icon_test.cpp`: the `MOSH_CALL_WINDOW=1` run in `.github/workflows/build-windows.yml` | the call child's own Win32 window class | the same test, which still checks the runner class app_links looks for |
| `scripts/macos-package.test.mjs`: "packaging signs the call window to inherit the sandbox before sealing the app" | signing of the `mosh-call-window` copy | none: the copy is no longer built |

## Verification on Linux, 2026-10-06

This run predates [ADR 0052](../ADR/0052-desktop-calls-in-the-main-window.md):
it exercised the separate call window process, which MOSH-101 removed.

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
