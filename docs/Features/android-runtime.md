# Android runtime ownership

`MoshApplication` lazily owns one Flutter engine for the process. The first
`MainActivity` still starts Dart through Flutter's ordinary launch path, retaining
the requested entrypoint and arguments. Creating the application does not start
Dart, open history or bypass the foreground DEK gate.

Replacing an Activity reattaches that same engine and plugin registry. Its Dart
isolate, provider tree, native session owners and selected native call stay in
place. No old Activity framework snapshot is restored over the running tree.
The existing Rust shared node, encrypted store, DEK and native media owner remain
unchanged. Finishing the Activity releases its UI, not the process-owned engine.

Ringtone playback and call/PiP configuration belong to the engine. Ringtone uses
the application context. PiP attaches only its window and privacy shield to the
current Activity, restores the existing call's parameters and drops that Activity
reference on detach. Camera permission prompts remain Activity UI; disposing an
outstanding prompt refuses that request without destroying the call owner.

This is the ownership preparation for [Android background waiting](../ADR/0048-android-background-waiting.md).
It does not implement a background service, cold-process ringing, a waiting
transport or a different key-release policy. Android can still reclaim the
entire process; retaining its engine is not an execution guarantee.

## Verification

The Android instrumentation runner recreates the real Activity three times and
checks that the already executing engine is neither replaced nor restarted. It
uses the Android SDK's instrumentation API and adds no test dependency. Build
and run on a connected ARM64 device using the isolated application ID:

```sh
flutter build apk --debug --target-platform android-arm64
cd android
./gradlew connectedDebugAndroidTest -PmoshLinkedDmTest
```

This checks Activity/engine lifetime, not a live media session. Also run the
existing independent-installation DM/native-call integration scenarios and, on
a real phone, exchange messages and keep a bidirectional call running through
navigation and Activity recreation. Check audio routing, floating video and PiP.
Use a disposable test profile for a recreation during a call; do not enable
Android's global "Don't keep activities" option on a primary profile.

During implementation, production Kotlin/Java and the instrumentation runner
compiled against Android 36/Flutter 3.44.8; Flutter analysis, the existing
presentation/navigation/ringtone tests and the host JNI context probe passed.
No Android device was connected. Real Activity execution, call continuity and
physical-phone acceptance remain unverified.
