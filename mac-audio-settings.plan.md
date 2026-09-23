# mac-audio-settings — plan

Brainstorm: `mac-audio-settings.brainstorm.md` (chosen: B for the clip dir,
A for the VP-off capture fix, C for the settings surface, Rust-side
audio-settings store).

## Goal

1. Voice messages send on macOS (fix the errno-2 `PathNotFoundException`).
2. A macOS callee is audible in calls (fix the silent-tap capture), with
   input/output device pickers so users can steer hardware themselves.
3. All settings live in a Discord-like settings screen behind a gear at the
   bottom of the sessions rail: Voice & Video (devices), Connection
   (advanced settings moved out of onboarding), About.

## Constraints

- Repo gates: `flutter analyze`, `dart format lib test integration_test`,
  `flutter test` full suite, `cargo test/clippy/fmt` (mosh-core), frb
  codegen regenerated + committed when the `api::` surface changes.
- file_max_loc 400; settings screen must be split into section widgets.
- No mocks in tests; device lists are stubbed through the real method
  channel / seam interfaces the same way existing tests do
  (`ScriptableGateway`, `setMockMethodCallHandler`).
- The DMG-side proof (VP-off, plist keys, cpal device pick) can only be
  validated via CI mac lane + a real Mac; host box is Linux.

## Testing methodology

- **Problem-2 fix:** widget test driving the real `record` method channel —
  capture start must target a path inside an explicitly created
  `mosh-voice/` directory (assert the directory exists and the `start`
  call's `path` arg lives inside it; assert recursive create happened even
  when the base dir is deleted beforehand).
- **Problem-1 fix:** unit test on the config builder — `RecordConfig` from
  the capture factory has VP knobs false on macOS, true elsewhere (inject
  `Platform.isMacOS`-style seam or a platform bool parameter).
- **Settings store:** Rust tests: save/load round trip, default off/none,
  unknown-device id tolerated; Dart provider tests via a scriptable seam.
- **Settings UI:** widget tests per section — device dropdown renders the
  enumerated labels, picking writes the store, gear row opens `/settings`,
  onboarding menu no longer contains the Advanced disclosure, Connection
  section controls work against a ScriptableBridge.
- Full-suite run before commit; `flutter analyze` + `dart format` clean.

## Steps (ordered)

### Phase 1 — Hotfixes (ship-blocking)

1. [x] **Voice clip dir fix** (`voice_composer.dart`): replace
   `getTemporaryDirectory()` with `getApplicationCachePath()` +
   `mosh-voice/` subdir + `Directory.create(recursive: true)` in
   `_capture()`; keep the m4a naming. Test first (fails: current code
   targets Caches root, dir never created).
2. [x] **macOS raw capture** (`record_voice_capture.dart`): extract the
   `RecordConfig` construction into a testable builder that takes a
   `isMacOS` bool (or use `Platform.isMacOS` behind a `@visibleForTesting`
   seam); macOS → `echoCancel/autoGain/noiseSuppress: false`. Test first.
3. [x] CHANGELOG entries for both fixes.

### Phase 2 — Rust audio surface

4. [x] `mosh-core/src/audio_settings.rs`: `AudioDevicesSetting
   {input_device_id: Option<String>, output_device_id: Option<String>}`,
   load/save to `audio-settings.json` in the data dir (copy the
   read_receipts.rs shape incl. tests).
5. [x] `api/audio_devices.rs` (new frb surface):
   - `list_output_devices() -> Vec<AudioDeviceInfo {id, name}>` via
     `default_host().output_devices()` (`id = DeviceId.to_string()`,
     `name = device.to_string()`).
   - `set_audio_devices(input_device_id: Option<String>,
     output_device_id: Option<String>)`, `audio_input_device_id() ->
     Option<String>`, `audio_output_device_id() -> Option<String>`
     (store-backed).
   - `voice_call_playback_start(output_device_id: Option<String>)` and
     `voice_call_ringtone_start(output_device_id: Option<String>)`: resolve
     via `DeviceId::from_str` + `device_by_id`; on parse/lookup failure log
     a `VOICE` line and fall back to the default device. Keep the
     no-arg-overload shape if frb optional args are clean (frb supports
     Option — prefer the single function with `Option`).
   - Rust tests: store round trip; resolver fallback (garbage id →
     default-device path without error).
6. [x] `flutter_rust_bridge_codegen generate` + commit generated files;
   `cargo test` + `cargo clippy --all-targets -- -D warnings` + `cargo fmt`.

### Phase 3 — Dart wiring

7. [x] `lib/src/state/audio_devices_provider.dart`: a small Notifier backed
   by the frb get/set calls + an input-device enumerator seam (wrap
   `AudioRecorder.listInputDevices` behind an injectable function so tests
   stub the channel).
8. [x] Input pick into `RecordVoiceCaptureFactory` + `VoiceComposer`:
   config gains `device: InputDevice(id)` when set. Keep the factories
   stateless: the orchestrator/composer read the setting at start time.
9. [x] Output pick: `CpalVoicePlaybackFactory.start()` + ringtone start call
   sites pass the stored output id (`voiceCallPlaybackStart(outputDeviceId:
   …)`).

### Phase 4 — Settings UI

10. [x] `/settings` route in `app_router.dart` (`AppRoutes.settings`);
    desktop: opens in the chat branch (branch B) like `/chat`; mobile:
    full-screen.
11. [x] Gear row pinned at the bottom of the sessions rail (`settings`
    icon + label, below the org sections, outside the scroll — mirror the
    RailNewButton placement pattern).
12. [x] `lib/src/features/settings/` slice:
    - `settings_screen.dart` — two-pane scaffold (section nav left, content
      right; ≤400 LOC, sections in own files), mobile degrades to a single
      scrolling column.
    - `voice_settings_section.dart` — input dropdown (record
      `listInputDevices`), output dropdown (frb `listOutputDevices`),
      test-ringtone button (plays via the existing ringtone start, 2 s,
      auto-stop), permission-denied hint reuses
      `voicePermissionDenied`.
    - `connection_settings_section.dart` — static peer, listen port,
      BindInterfaceField, ReadReceiptsToggle (moved from onboarding).
    - `about_settings_section.dart` — version + crypto notice.
13. [x] Strip the Advanced + About disclosures from `onboard_menu.dart`
    (identity chip + tiles remain); gear becomes the only home for those
    controls.
14. [x] l10n `app_en.arb` + `app_ru.arb`: settings title, section labels,
    device dropdown labels ("System default" + device names),
    test-ringtone label, gear tooltip. `flutter gen-l10n`.

### Phase 5 — Verification

15. [x] New tests: composer dir fix, capture-config builder, store
    round trip (Rust), resolver fallback (Rust), settings screen sections,
    gear routing, onboarding regression (no Advanced disclosure).
16. [x] `flutter analyze`; `dart format lib test integration_test`;
    full `flutter test`; `cargo test` + `cargo clippy` + `cargo fmt`;
    confirm no drift (`flutter_rust_bridge_codegen generate` idempotent).
17. [x] CHANGELOG `[Unreleased]`: two Fixed + one Added (settings screen +
    device pickers).
18. [x] Commit (Conventional Commits; split: fix commits for phase 1/2, feat
    for settings UI).

## Gotchas found during the work (for the next agent)

1. **Fake-async kills real async IO** (bit me again, and it is in the old
   plan file too): `Directory.create()` (async) inside a widget test never
   resolves — the method-channel reply resolves, but the real filesystem
   operation waits for an event loop turn fake-async never takes. Use
   `createSync(recursive: true)` for any directory the widget tree needs
   mid-test. Symptom: the tap "does nothing" — no error, no started call.
2. **`record` 7.1.1's `dispose()` deadlocks a widget test** after a real
   `start()`: `_disposeState` cancels the state EventChannel subscription,
   which sends a `cancel` method call that `setMockMethodCallHandler` does
   NOT answer (EventChannels talk over `receiveBroadcastStream`, whose
   onListen/onCancel go through the same-named MethodChannel — answer
   `listen`/`cancel` by prefix via `allMessagesHandler` if a test must
   dispose; otherwise leave the recorder undisposed and let the pending
   amplitude timer fail the invariants — the OLD permission tests dodge
   this by never stopping).
3. **frb sync calls in widget-tree code** (`audioInputDeviceId()` in the
   composer's `_capture`) throw `Bad state: flutter_rust_bridge has not
   been initialized` under `flutter test` — and a `try/catch` around them
   swallows the failure into the onError path, so the test sees "nothing
   happened". Any frb read reachable from a widget must be behind an
   injectable getter defaulting to the frb call (the seam pattern used for
   `inputDeviceId` on VoiceComposer / RecordVoiceCaptureFactory /
   ConversationComposer).
4. **`InviteFlowState.copyWith` could not reset `staticPeer` to null** —
   found by the new connection-section test: a plain `String?` param +
   `?? this.staticPeer` makes "reset" indistinguishable from "keep".
   Fixed with the `_unset` sentinel-object pattern; any nullable state
   field with a reset path needs it.
5. **`enterText('')` on an already-filled TextFormField under the test
   IME** swallows the edit in some sequences (focus/ordering dependent);
   don't write tests that assert the empty-clear path through
   `tester.enterText` — assert the store mapping at its ends instead.
6. **frb codegen mirrors EVERY pub fn in an `api::` module** — a helper
   returning a non-bridgeable type (`cpal::Device`) must live outside
   `api::` (ours: `crate::audio_devices::resolve_output_device`), or
   codegen emits opaque glue for it and the crate stops compiling.
7. **`InputDevice` requires `label`** (`const InputDevice(id: …)` does not
   compile); platform matchers use the id, so `label: picked` (the id
   again) is the honest placeholder.

## Failing-test baseline (recorded before edits)

- Full suite before any change: **851 passed / 5 skipped / 0 failed**
  (flutter), **359 passed / 6 ignored** (cargo, audio_devices filter: 5).
- The 12 failures seen mid-work were all caused by this task's own edits
  (Advanced disclosure removal orphaned the old onboarding tests; frb call
  in `_capture` broke widget tests) — none pre-existing on main.
