# Android call compatibility and reported regressions

## Scope

Make Android and desktop use the existing authenticated native audio/video call
protocol and RingRTC/WebRTC engine over Moss. Preserve the desktop media path,
selected-device authority and encryption. Include the reported Android navigation,
audio-device and invitation-button issues and the crash-reporter failure found
in the supplied log.

## Implementation order

1. Decode the supplied release traces with matching build-ID symbols. Adapt Rust
   Sentry events to the Dart SDK and isolate reporting failures from the app.
2. Handle system Back at the mobile shell boundary after nested routes/selection
   have had their opportunity to consume it. Preserve the chat and draft.
3. Inspect rendered invitation actions. The existing shared style gives all
   three controls 40 px painted height and 48 px touch height in English/Russian;
   do not change geometry without reproducing the reported mismatch.
4. Build the pinned native media engine and WebRTC for Android ARM64. Signal's
   official Android artifact has a null native-factory stub, so compile the same
   pinned source with the native factory enabled; preserve injected Moss media.
   Package it through the existing Android preparation.
5. Initialize Android application/JVM context for native audio. Use real Android
   audio devices and communication routing; retain the system-default choice.
6. Adapt Android camera capture and permissions to the existing native owner and
   bounded frame pipeline. Keep capture/native resources out of Dart UI ownership.
7. Enable the same media protocol and native presentation client on Android. Reuse
   existing call controls and video rendering inside the mobile application.
8. Build a signed ARM64 release APK with production billing configuration and
   independently verify its signature, manifest, native libraries and alignment.

## Checks and risks

- Focused caller-facing regressions for event parsing/stream failures, system Back,
  media admission and Android platform adapters. Inspect button geometry visually.
- Format/analyze and relevant Flutter/Rust suites; regenerate bindings if the
  bridge changes. Review security/ownership before publishing a test artifact.
- Android media must use the same codec/crypto/negotiation as desktop; accepting an
  incompatible offer without implementing its media is not a fix.
- No phone is connected to this workspace. Hardware camera/audio, Bluetooth,
  permissions and Android-to-desktop media require physical acceptance.
- Incoming calls when Android has suspended/killed the app are separate from
  foreground interoperability; do not claim that a compiled APK proves either.
