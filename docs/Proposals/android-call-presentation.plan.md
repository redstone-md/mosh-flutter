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
