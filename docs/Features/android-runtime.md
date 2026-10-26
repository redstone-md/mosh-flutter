# Android runtime ownership

`MoshApplication` lazily owns one Flutter engine for the process. The first
`MainActivity` starts Dart through Flutter's ordinary launch path, retaining
the requested entrypoint and arguments. A cold `MoshWaitingService` can instead
start that same engine after immediately posting its quiet foreground
notification. Creating the application alone does not start Dart or open history.
Both entries use the same installation DEK and native owners; cold execution
does not grant interactive access to chats.

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

The non-exported specialUse service implements execution eligibility for
[Android background waiting](../ADR/0048-android-background-waiting.md).
Setup and Stop waiting are durable installation choices. Stop is committed
before acknowledgement; fresh native work facts release the service after
admitted calls/transfers finish. An intent revision rejects replies captured
before a later Stop or lifecycle transition.

Ordinary reclamation uses Android's sticky service restart. BOOT_COMPLETED uses
credential-encrypted preferences after first unlock and respects saved Stop.
An OS user-requested exit fences automatic restart until a real Activity reopen;
reopening never changes a separately saved Stop waiting choice. There is no
restart alarm or watchdog. OEM task removal may be reported as a user-requested
exit; it cannot safely be treated as permission to revive an application.

One default-network observer forwards coalesced hints to the existing native
Moss owner on a bounded worker. Startup and handover use bounded partial wake
locks (15 and 10 seconds); continuous CPU wakefulness is not assumed. The quiet
service notification reflects actual native reachability and permission limits,
not merely the existence of a foreground service. Android can still reclaim
the process, and Doze/network/energy acceptance requires physical measurements.

The native message publisher reuses the installed notification builder and
checks current app access, device lock and independent name/text consent
immediately before OS publication. Locked content is generic by default,
including public versions and OS metadata. Existing posted notifications are
reduced when native access or consent changes. An older durable revision cannot
overwrite a newer posted notification. Notification permission failure never
acknowledges a delivery record.

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

The waiting intent/drain/privacy policies also run through
`node scripts/android-context-check.mjs`. Native app and notification
instrumentation sources compile. On an isolated, notification-enabled device,
pass `-e waitingNotifications true` to the instrumentation runner to exercise
actual OS extras, privacy reduction and stale revision replay. That check has
not been executed without a device.
