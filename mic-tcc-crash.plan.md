# Plan: macOS TCC crash on chat open — microphone permission

Brainstorm: [mic-tcc-crash.brainstorm.md](mic-tcc-crash.brainstorm.md)

## Task goal and scope

Kill the chat-open TCC crash (SIGABRT, missing `NSMicrophoneUsageDescription`)
and the same hole on iOS/Android, and move the mic permission request from
chat open to the mic tap.

- In scope: `macos/Runner/Info.plist`, both macOS entitlements files,
  `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`,
  `VoiceComposer` permission flow (ask-on-tap), a localized denial label,
  `CHANGELOG.md`, feature-doc note, tests for the new flow.
- Out of scope: call capture code (already requests via
  `RecordVoiceCapture.start()`), no `api::` changes, no bridge codegen, no
  Windows/Linux changes (no TCC there; `record` start/hasPermission works
  without a usage key), no DMG signing.

## Constraints and risks

- File budget: `voice_composer.dart` is 413 LOC vs the 400 budget — the
  rework must not grow it (see step 4).
- Tests may break where the mic button previously collapsed to
  `SizedBox.shrink()`: any composer-adjacent layout/count assertions.
  Checked in the baseline step, fixed by scoping finders, not by weakening
  assertions.
- macOS entitlements/plist prove out only on a real Mac build; this box is
  Linux. Validation here: `flutter analyze` + full Dart suite + XML sanity
  check (`plutil` unavailable; xmllint if present).
- The `record` package's method channel (`com.llfbandit.record/messages`) is
  scriptable via `TestDefaultBinaryMessengerBinding` (repo precedent:
  `desktop_drop`/`window_manager` channel tests) — tests drive the REAL
  plugin seam, not a fake recorder.

## Testing methodology

- Flows covered:
  1. Mic button renders with no permission probe at mount (no
     `hasPermission` method call at init — asserted by recording channel
     traffic while pumping).
  2. Tap mic with granted permission → recording phase renders (dot,
     timer, discard, stop).
  3. Tap mic with denied permission → no recording phase, snackbar with
     the localized denial label via `onError`.
  4. Denied-then-granted: the same tap retries the request (macOS
     `.denied` re-ask behavior differs by OS, but the composer must always
     re-request on tap — never cache a denial).
  5. Platform files: plist/entitlements/manifest contain the right keys
     (an XML-parse test, keeping config drift visible in the suite).
- How: widget tests against the real `record` method channel (the repo's
  channel-stubbing pattern), plus one `flutter test` file asserting the
  platform config files. Quality bar: named assertions per flow, no
  `expect(true)` smokes, full suite green.
- Commands: `flutter analyze`, `flutter test` (full), `flutter gen-l10n`
  before analyze/tests (new ARB key), `dart format lib test`.

## Already-failing tests

Baseline (before changes): to be recorded by running the full suite first —
the plan expects composer-adjacent layout tests may fail once the mic button
renders in tests; each failure gets its own checklist item below with
root cause and fix path.

- [x] Baseline recorded after `flutter gen-l10n` + `flutter test` full run:
      **842 passed, 5 skipped, 0 failed** (one non-fatal `warnIfMissed`
      tap warning in `attachment_card_preview_test.dart`). No pre-existing
      failures to track.

## Ordered steps

1. **Baseline**: `flutter pub get` (ensure l10n generated), `flutter test`
   full. Record pass/fail counts here before touching anything.
2. **Platform keys (the crash itself)**:
   - `macos/Runner/Info.plist`: add `NSMicrophoneUsageDescription` = "Mosh
     uses the microphone for voice messages and calls."
   - `macos/Runner/DebugProfile.entitlements` +
     `Release.entitlements`: add `com.apple.security.device.audio-input`
     = true.
   - `ios/Runner/Info.plist`: same usage string.
   - `android/app/src/main/AndroidManifest.xml`: add
     `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`.
   - XML well-formedness check on the four files.
   - Test: `test/platform/mic_permission_config_test.dart` parses each file
     (real files via `File.readAsString`, no fixtures) and asserts the keys.
3. **l10n**: add `voicePermissionDenied` to `app_en.arb` + `app_ru.arb`,
   `flutter gen-l10n`.
4. **VoiceComposer rework** (`lib/src/features/shared/voice_composer.dart`):
   - Delete `_supported` / `_checkSupported`; the mic button always renders.
   - `_startRecording`: `if (widget.disabled) return;` then
     `hasPermission()` (request: true) → on false, `widget.onError(l.voice…)`
     — wait, `VoiceComposer` receives labels as strings, and a localized
     denial needs the label threaded through `ConversationComposer` like
     the other five voice labels (adds one required param). Add
     `permissionDeniedLabel` to both widgets.
   - `onPermissionDenied` is surfaced via the existing `onError` snackbar
     seam — no new UI surface.
   - `_VoiceComposerState` shrinks: `initState` body empty, two fields +
     one method deleted. Net LOC change ≈ −8 to −15 with the new branch —
     file stays under 400.
5. **Tests for the new flow**:
   `test/features/shared/voice_composer_permission_test.dart`:
   - Channel stub for `com.llfbandit.record/messages`: `create` → null,
     `hasPermission` → scripted true/false, `start` → null, `stop` → path,
     `cancel` → null, `dispose` → null, `isRecording` → false,
     `getAmplitude` → zeros, event channels ignored.
   - Flow 1: pump, assert no `hasPermission` invocation at mount, mic icon
     renders.
   - Flow 2: stub granted → tap → recording row renders; tap stop → review
     row renders; send asserts the `VoiceSend` path/mime.
   - Flow 3: stub denied → tap → no recording row, `onError` got the
     denial label, mic still rendered (can re-tap).
   - Also update `conversation_composer_test.dart` /
     `composer_typing_emit_test.dart` / `hit_area_test.dart` constructors if
     the new required label breaks them, and scope any layout assertion the
     always-on mic button disturbs.
6. **Docs**: `CHANGELOG.md` under `## [Unreleased]` → `### Fixed` entry
   (macOS TCC crash + iOS same class + Android permission + ask-on-tap).
   Note in `docs/Features/field-log.md` only if it has a voice section —
   checked: it does not (voice-call frames are there, mic permission is not
   transport), so CHANGELOG only. ADR not needed: no architecture/boundary
   change.
7. **Verification**: `flutter gen-l4n` typo-guard — run the real commands:
   `flutter gen-l10n`, `dart format lib test`, `flutter analyze`,
   `flutter test` full. All green = done criterion.

## Final validation (ordered)

1. `flutter gen-l10n` — regenerates localizations with the new key.
2. `dart format lib test integration_test` — format gate.
3. `flutter analyze` — static gate.
4. `flutter test` — full behavior proof (838+ tests).
5. `xmllint --noout` on the four touched XML files — plist/manifest sanity
   (CI mac lane is the ultimate arbiter for entitlements at build time).

## Done criteria

- [x] Baseline recorded; failures (if any) each tracked with root cause:
      842 passed / 5 skipped / 0 failed before changes.
- [x] All four platform files carry their keys; config test green.
- [x] Mic button always renders; permission requested only on tap; denial
      surfaces localized message via `onError`.
- [x] New permission-flow tests green; full suite green (851 passed /
      5 skipped / 0 failed, +9 new tests); analyze clean.
- [x] CHANGELOG entry written.
- [x] `voice_composer.dart` 398 LOC (≤ 400 budget).

### Verified fix summary (final run)

- `flutter gen-l10n`: regenerated with `voicePermissionDenied`.
- `dart format lib test integration_test`: clean.
- `flutter analyze`: no issues.
- `flutter test` full: **851 passed, 5 skipped, 0 failed**.
- XML sanity: all five touched files parse.

### Gotchas found during the work (for the next agent)

- Widget tests + the `record` package: `AudioRecorder()` sends `create`
  over the method channel and `await create/…` never resolves unless a
  `setMockMethodCallHandler` stub answers it — the bare recorder deadlocks
  a widget test even with no plugin registered.
- Real async IO (`Directory.systemTemp.createTemp`) inside `testWidgets`
  hangs the fake async zone; use `createTempSync`/`deleteSync`.
- No `pumpAndSettle` while a recording is live: the elapsed timer is
  periodic (setState every 200 ms), settle never terminates — pump fixed
  frames instead.
