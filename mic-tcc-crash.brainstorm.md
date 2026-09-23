# Brainstorm: macOS TCC crash on chat open — microphone permission

## Problem

Both 0.9.1 `.ips` reports (macOS 15.8.1, Intel Mac mini) die identically:
SIGABRT in the TCC namespace — "attempted to access privacy-sensitive data
without a usage description … must contain an
NSMicrophoneUsageDescription key".

Path to the crash:

1. Chat opens → `ConversationComposer` mounts → `VoiceComposer` inside it.
2. `initState` → `_checkSupported()` → `_recorder.hasPermission()`
   (`request: true` by default in `record` 7.1.1).
3. `record_macos` sees `.notDetermined` and calls
   `AVCaptureDevice.requestAccess(for: .audio)`.
4. `macos/Runner/Info.plist` has no `NSMicrophoneUsageDescription`, so TCC
   kills the process before any dialog appears.

Rust / mosh_core is not involved: the crashing thread is pure TCC +
libdispatch.

Same hole on the other targets (not a crash on macOS any more, but broken
elsewhere):

- `ios/Runner/Info.plist`: same missing key → identical crash on iOS at chat
  open.
- `android/app/src/main/AndroidManifest.xml`: no `RECORD_AUDIO` declared by
  the app. The `record_android` plugin merges `RECORD_AUDIO` into the APK
  itself, so the runtime request would actually work — but the app manifest
  must declare what the app uses; relying on a plugin's merge is fragile.
- The sandboxed macOS app additionally needs
  `com.apple.security.device.audio-input` in both entitlements files, or
  the mic is silently denied even with the plist key.

## UX defect in the same code path

The system permission dialog pops on the first chat open — before the user
expressed any intent to record. Standard messenger UX (and the user's
direction): ask on the mic tap, not on chat open.

Constraint discovered in the code: `_supported` (which gates the whole
widget to `SizedBox.shrink()`) is derived from `hasPermission()`. With
`request: false`, a `.notDetermined` status returns `false` — so a naive
switch to `request: false` in `initState` would hide the mic button for
every fresh install, and the user could never grant the permission from the
app.

Also verified in `record_macos` source: `start()` does NOT request
permission by itself. So the tap handler must call `hasPermission()` (which
requests when `.notDetermined`) before `_capture()` — for voice messages
and implicitly for calls (`RecordVoiceCapture.start()` already does this
itself).

## Options

### A. Plist + entitlements only (minimal fix)

Add the keys, keep `hasPermission()` (request: true) in `initState`.

- Pro: one-file diff per platform, zero Dart changes.
- Con: keeps the ambush dialog on every fresh chat open; the TCC dialog
  pops while the user is looking at something else. iOS shows the same
  behavior. The dialog would also appear for users who never record.
- Verdict: fixes the crash, keeps a UX defect the user explicitly flagged.

### B. Plist + entitlements + ask-on-tap (chosen)

Add the platform keys; drop the permission check from `initState` entirely;
the mic button always renders; the tap handler requests permission, and a
denial surfaces through the existing `onError` → snackbar path with a
localized message.

- Pro: the system dialog appears at the moment of intent (mic tap), the
  standard pattern; no TCC call at chat open at all, so the crash class is
  gone by construction, not just patched; the button is always reachable
  so a user who denied once can re-request (macOS re-asks until denied
  explicitly; iOS/Android re-ask or bounce to settings).
- Con: slightly more code (a permission branch in `_startRecording`, a new
  localized label threaded through the composer), and a new widget-state
  shape to test.
- Why the constraint is satisfied: nothing gates the mic button on
  permission any more. `_supported` and `_checkSupported` are deleted.

### C. Permission provider / global pre-flight (ask once at app start)

A Riverpod provider that requests mic permission on first launch.

- Con: same ambush-dialog problem, one screen earlier; more machinery;
  asks every user including those who never record. Rejected.

## Recommendation

**Option B.** Platform keys (macOS plist + both entitlements, iOS plist,
Android manifest) plus the ask-on-tap rework in `VoiceComposer`, with the
denial surfaced through the existing `onError` snackbar seam and a new
localized `voicePermissionDenied` string.

## Risks

- The mic button now renders in every existing widget test that pumps a
  conversation composer (it used to collapse to `SizedBox.shrink()` because
  `hasPermission` fails without a plugin). Tests that count `IconButton`s
  or assert layout widths near the composer may need scoping updates; the
  composer row grows by one 40px target, so narrow-surface tests could hit
  overflow — must be checked against the full suite, not assumed.
- `record_macos` `start()` never requests on its own: the tap handler MUST
  request before `_capture()`, or a granted-state user gets a silent
  failure instead of a dialog (regression for nobody today, but a trap
  for the future).
- Entitlements + plist only prove out on a real macOS build; this Linux
  box cannot run Xcode. Validation here is `flutter analyze` + full Dart
  suite + plutil-style XML sanity; the DMG rebuild has to happen in CI
  (`build-macos.yml`) or on a Mac.
