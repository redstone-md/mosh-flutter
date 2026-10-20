# Android call follow-up

Scope: correct the caller shown by new call-history entries; use Android ringtone
audio attributes; make calls minimizable, with draggable in-app video and Android
Picture-in-Picture for an active video call. Reuse the current signaling, native
media owner, renderer and recordings. No protocol, dependency or database changes.

1. Lock down outgoing/incoming history attribution at the native session boundary.
2. Add Android playback behind `RingtonePlayer`, respecting ringer mode and
   stopping obsolete playback even when native startup completes late.
3. Add an explicit minimize action, compact voice controls and draggable video.
4. Integrate system PiP, showing video only (never the chat), keeping the current
   media owner alive and restoring ordinary navigation on return. Stop capture
   when the user closes PiP rather than leaving an invisible call behind.
5. Run focused behavior tests, Flutter checks, Kotlin compilation and Rust checks;
   review, update PR #93 and produce a verified signed ARM64 APK.

Risks: actual ringtone volume, OEM camera/audio behavior and Home/Back/PiP
transitions require a physical Android device. Existing incorrectly attributed
history has no reliable direction marker and is not rewritten speculatively.

The existing multi-phase `CallView`/`CallModalCard` builders and routed widget
scenario remain exceptions to the 50-line function limit: keeping phase controls
and the ordered navigation/PiP scenario together makes their lifecycle explicit.

## Implementation checks

Flutter analyze and Kotlin compilation pass. The call/dialog/PiP regression
passes for voice and video, including a root dialog at a 256×144 PiP viewport.
Rust unit and integration suites pass with the local real-Moss tracker. Both
code-review passes found no remaining issues after the PiP fixes. Physical
ringtone routing, camera continuity and system gestures still require a phone.

## Changed files

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/app/mosh/mosh/MainActivity.kt`
- `android/app/src/main/kotlin/app/mosh/mosh/MoshCallPresentation.kt`
- `android/app/src/main/kotlin/app/mosh/mosh/MoshRingtone.kt`
- `assets/audio/README.md`
- `docs/Features/voice-calls.md`
- `docs/Proposals/android-call-presentation.plan.md`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ru.arb`
- `lib/main.dart`
- `lib/src/features/conversation/call_log_entry.dart`
- `lib/src/features/conversation/conversation_message_row.dart`
- `lib/src/features/voice_call/android_call_presentation.dart`
- `lib/src/features/voice_call/android_pip_overlay.dart`
- `lib/src/features/voice_call/android_ringtone.dart`
- `lib/src/features/voice_call/call_controls.dart`
- `lib/src/features/voice_call/call_modal_card.dart`
- `lib/src/features/voice_call/call_notification_details.dart`
- `lib/src/features/voice_call/call_video_stage.dart`
- `lib/src/features/voice_call/call_view.dart`
- `lib/src/features/voice_call/floating_call_view.dart`
- `lib/src/features/voice_call/mobile_call_frame.dart`
- `lib/src/features/voice_call/mobile_call_host.dart`
- `lib/src/features/voice_call/voice_call_host.dart`
- `lib/src/features/voice_call/voice_call_layer.dart`
- `lib/src/state/production_provider_overrides.dart`
- `mosh-core/src/private_dm_runtime/calls/boundary_tests.rs`
- `mosh-core/src/private_dm_runtime/calls/boundary_tests/history_direction.rs`
- `mosh-core/src/private_dm_runtime/calls/history.rs`
- `pubspec.yaml`
- `scripts/android-package-verify.sh`
- `test/features/conversation/call_log_entry_test.dart`
- `test/features/conversation/dm_message_row_call_event_test.dart`
- `test/features/voice_call/android_call_presentation_test.dart`
- `test/features/voice_call/android_pip_lifecycle_test.dart`
- `test/features/voice_call/android_ringtone_test.dart`
- `test/features/voice_call/voice_call_layer_test.dart`
- `test/support/native_call_fixture.dart`
