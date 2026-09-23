# macOS audio: silent call capture, voice-message temp file, device pickers + Discord-like settings

Date: 2026-09-23. Source: user reports from a Mac running the 0.9.3 DMG + a feature ask.

## The three asks

1. **Silent call capture on macOS.** When the caller rings a macOS user, the
   caller cannot hear the macOS user, but the macOS user hears the caller.
   The user suspects the missing mic picker; the evidence below says the
   primary cause is different, with the picker as the needed feature on top.
2. **Voice-message send fails on macOS.** `PathNotFoundException` on
   `/Users/Eugen/Library/Containers/app.mosh.mosh/Data/Library/Caches/app.mosh.mosh/mosh-voice-…​.m4a`
   (errno 2, "No such file or directory") when the sender taps Send on a
   recorded voice message.
3. **Discord-like settings screen** in a gear icon at the bottom-left of the
   sessions rail: connection settings (moved out of the onboarding menu's
   Advanced disclosure), input device, output device — "all settings".

## What the evidence says

### Problem 2 — root cause is proven (static)

- `VoiceComposer._capture()` builds the temp file inside
  `getTemporaryDirectory()` — on macOS `path_provider_foundation` maps that
  to `NSCachesDirectory` **plus the bundle id appended**
  (`…/Library/Caches/app.mosh.mosh/`), but the plugin only `create()`s the
  directory for `getApplicationCachePath` / `getApplicationSupportPath`,
  never for `getTemporaryPath`.
- `record_macos`' `RecorderFileDelegate.start()` does
  `deleteFile(path:)` then `AVCaptureFileOutput.startRecording(to:)`. It
  never creates the parent directory; `AVCaptureFileOutput` failing to
  create its output file is reported **asynchronously on the file output's
  delegate** (`recording(_:isInterrupted:error:)`), which the plugin does
  not surface — and `stop()` still returns the path. So recording "succeeds"
  silently, the review player plays nothing, and `sendVoice`'s
  `File(path).readAsBytes()` throws exactly the user's errno-2
  `PathNotFoundException`.
- Windows does not hit this (`record_windows` creates the parent dir;
  `path_provider_windows`' temp dir exists), iOS does not append the bundle
  suffix on the temp path — macOS-only, matching both field reports.

**Fix:** stop using `getTemporaryDirectory()` for the recorded clip; use
`getApplicationCachePath()` (the plugin creates it) or create the directory
ourselves. The clip is also not really "temporary" in the cache sense — it
lives until the send completes; a dedicated subdirectory
(`<cache>/mosh-voice/`) created explicitly with `Directory.create(recursive:
true)` is immune to both plugin quirks and to any future plugin change.

### Problem 1 — root cause is proven (static) with strong external corroboration

Asymmetry (callee hears caller, caller does not hear callee) means the macOS
callee's **capture** produces silence while their **playback** (cpal) works.

- Call capture goes through `record`'s `startStream` with
  `RecordConfig(echoCancel: true, noiseSuppress: true, autoGain: true)`.
- On macOS `record_macos` implements that with `AVAudioEngine` +
  `setVoiceProcessingEnabled(true)` on the input node, tap on bus 0 in the
  node's own format, `AVAudioConverter` to the requested 48 kHz mono i16.
- Apple's VoiceProcessingIO on macOS is a **duplex** unit: the
  well-documented failure mode (Quill RCA-001; StackOverflow 59992239 and
  77994207; OpenAI realtime thread) is that an input-only graph with VP
  enabled silently renders zero-filled tap buffers on some devices/routes —
  exactly "the peer's meter never moves". `record_macos` builds an input-only
  graph and does no output-side wiring, so it sits right in the known-bad
  configuration.
- This ALSO explains why the issue surfaced only now-ish: it depends on the
  Mac's device set (aggregate devices, Bluetooth headsets are the classic
  silent-tap routes).

**Fix (capture):** stop asking for Apple voice processing on macOS —
`echoCancel/autoGain` are cross-platform knobs; drive them platform-aware:
off on macOS (raw capture), unchanged elsewhere. Do it in the call capture
(`RecordVoiceCaptureFactory`) where the config is built. Note the voice
composer is NOT affected (it records via `AVCaptureSession` file output, no
`AVAudioEngine`).

**Feature (on top):** device pickers. `record` exposes
`listInputDevices()` (`InputDevice{id,label,…}`) and
`RecordConfig.device` — supported on macOS (AVCaptureDevice uniqueID), iOS
(port descriptions), Windows (MMDevice), Linux (PipeWire/pulse). Output
enumeration/selection has to be added to mosh-core via cpal 0.18
(`Host::output_devices()`, `DeviceId` stringifies as `host:device` and
round-trips through `FromStr`, and `device_by_id` re-resolves a persisted
id). Playback + ringtone currently hardcode `default_output_device()`;
thread an optional stored device id through `voice_call_playback_start` /
`voice_call_ringtone_start`.

## Options considered

### Problem 2 options

- **A. Keep `getTemporaryDirectory()`, create the dir in `_capture()`.**
  Works, but keeps the file in a directory the platform may purge mid-flow
  (macOS can evict Caches) and keeps us dependent on the plugin's
  bundle-suffix behavior.
- **B. (chosen) `getApplicationCachePath()` + explicit
  `Directory('mosh-voice').create(recursive: true)` subdirectory.** The
  plugin guarantees the base exists; the explicit recursive create makes
  the invariant ours (fail loudly at capture time, not at send time); the
  subdir isolates our clips and makes cleanup trivial. On Android this maps
  to `cacheDir` (fine for a send-transient file), on Windows
  `%LOCALAPPDATA%\…\Cache` (fine), Linux `~/.cache` (fine).
- C. Record into memory (`startStream`) and write the file ourselves.
  Replaces one native pipeline with a hand-rolled AAC muxer — rejected.

### Problem 1 options

- **A. (chosen) macOS: `echoCancel/autoGain/noiseSuppress` → false in
  `RecordVoiceCaptureFactory`.** One-line-per-knob fix at the config source;
  raw capture never hits the VP duplex bug; Opus DTX already covers silence.
  Echo risk on speakerphone exists but "peer is silent" strictly beats "peer
  is inaudible"; the old React app shipped VP too and had the same latent
  bug class.
- B. Patch `record_macos` (fork/PR) to build the duplex graph properly.
  Correct long-term but a native-plugin change we cannot verify on this
  Linux box; too slow for the hotfix.
- C. WebRTC-native stack. Out of scope for a hotfix; the cpal+record
  pipeline is fine once VP is off.

### Settings screen options

- **C. (chosen) New `/settings` route + gear row at the bottom of the
  sessions rail** (below the org sections, pinned outside the scroll — the
  same place Discord puts it). Sections (Discord-like: left nav of section
  keys inside the screen, content pane on the right; desktop two-pane,
  mobile single pane with a section dropdown):
  - **Voice & Video**: input device dropdown (from `record.listInputDevices`),
    output device dropdown (new frb: `list_output_devices`), a
    "test ringtone" button (reuses `voice_call_ringtone_start`) for the
    output pick, and a mic test later (out of scope).
  - **Connection**: the three onboarding-Advanced controls moved here —
    static peer, listen port, bind-interface (relaunch-gated) + read
    receipts toggle.
  - **About**: version + crypto notice (reuses the onboarding About
    disclosure content).
- A. Modal/drawer from the gear. Rejected: a settings *surface* with three
  sections + device dropdowns needs a route for deep-linking and testing;
  modals fight the rail's tight width.
- B. Put settings in the titlebar. Wrong layer: the gear belongs to the rail
  (per user: "в иконку настроек в сайдбаре слева снизу").

### Persistence + seams for device picks

- **(chosen)** Rust-side `audio-settings.json` in the data dir (the exact
  `read-receipts.json` precedent: non-secret, must be readable pre-runtime):
  `{"input_device_id": "…", "output_device_id": "…"}`.
  - Input pick: Dart reads the setting (new frb getters/setters) and passes
    `device: InputDevice(id)` into `RecordConfig` for both the call capture
    and the voice composer.
  - Output pick: new frb `list_output_devices()` + pass the stored
    `output_device_id` into `voice_call_playback_start(id)` and
    `voice_call_ringtone_start(id)`; `None`/empty → default device.
    `DeviceId::from_str` failure or unknown id → log + default device
    (device unplugged must never break a call).
  - Why not `shared_preferences`: adds a new dep for something mosh-core
    already does with a JSON file pattern; the Rust side needs the output id
    anyway (playback lives in Rust), so one store serves both sides.
- The seam changes stay inside the existing factories: production overrides
  construct `RecordVoiceCaptureFactory()` / `CpalVoicePlaybackFactory()` —
  they gain an optional-device seam (read from the settings provider), tests
  keep overriding with noop/scriptable fakes untouched.

## Risks

- cpal `DeviceId` string stability across replug/reboot is "where possible"
  per cpal docs — the fallback-to-default path must be the designed
  behavior, not an error path.
- `record`'s `InputDevice` on iOS lists ports, not physical devices; the
  dropdown there will be coarse. Acceptable (mobile is second per repo
  priority; the ask is desktop-first).
- Onboarding menu loses its Advanced disclosure — the gear takes over. The
  onboarding identity-chip (display name) stays where it is.
- macOS-only code paths (voice processing off; the VP bug itself) cannot run
  on this Linux box: verification is `flutter analyze`/`flutter test` +
  `cargo check/clippy` on host + the CI mac lane building the DMG; the
  user's next Mac call is the real proof.
- The `/settings` route must keep working on mobile (single-pane shell) —
  the two-pane settings layout degrades to one column below the shell's
  width breakpoint.

## Decision

Do:
1. Problem-2 hotfix: voice clip dir → explicit `mosh-voice/` subdir under
   `getApplicationCachePath()`, created recursively at capture start.
2. Problem-1 hotfix: macOS raw capture (VP knobs off on macOS) in
   `RecordVoiceCaptureFactory`.
3. Rust: `audio-settings.json` store + frb surface (get/set input+output
   ids, `list_output_devices`), output id threaded through playback +
   ringtone starts.
4. Dart: audio-settings provider; input device into call capture + voice
   composer configs; output id into the two frb start calls.
5. UI: `/settings` route, gear row pinned at the rail bottom, Discord-like
   sectioned settings screen (Voice & Video / Connection / About), advanced
   settings removed from the onboarding menu.
6. l10n (en+ru) for every new string; tests for each layer; CHANGELOG.

Out of scope: video calls, a mic-test meter, per-conversation devices,
Bluetooth-route policy, changing the ringtone synth, Android UI polish of
the device lists.
