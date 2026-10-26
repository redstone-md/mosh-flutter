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

## Call presentation and media

The same waiting adapter consumes durable native call revisions. AndroidX
CallStyle supplies incoming/ongoing notifications and its older-Android fallback.
Generic lockscreen versions retain Answer/Decline while omitting caller identity.
Immutable explicit intents contain only a 256-bit one-use capability; session
and call identifiers remain in the native encrypted ledger. Intent identity uses
a hash so routine system intent diagnostics do not print that capability.
Call intent data is removed before Flutter route handling; ordinary invitation
deep links retain their existing behavior.

A bounded application queue retains actions until that same Dart owner attaches.
Full-screen presentation validates/selects a call without accepting it. Explicit
Answer follows the current native capability, visible permission and acceptance
path. Full-screen intent availability is checked on Android 14+; a denied grant
retains an actionable notification. No chat authentication grant is created.
An ephemeral native call-only flag covers even a chat grace period while a call
is shown over keyguard. Actual device unlock or final call completion removes
that window mode without changing the original chat deadline.

Before capture, the visible Activity and actual microphone/camera permissions
must allow typed foreground-service promotion. Promotion invalidates old work
facts, so a delayed zero-call reply cannot remove a newly admitted media type.
Idle waiting explicitly starts without microphone/camera types, including on
Android 10–13. Current native user-work facts drop media types after the call.
The existing ringtone player handles both Dart outgoing and native incoming
audio with separate identities, original expiry, silent/vibrate and DND limits.
No second player, engine, media owner or ringtone plugin is registered.

## User-started file transfers

Attachment offers create no download. Explicit user work uses a UIDT JobScheduler
job on Android 14+, or a separate correctly typed dataSync service earlier.
An actual late authenticated receiver request uses an ordinary constrained job;
an outstanding offer alone holds neither a job nor an active mesh. Scheduling
acceptance does not authorize bytes: actual OS start/stop callbacks update a
short native JNI grant, independently of Dart. Per-operation generations and a
process incarnation fence stale callbacks. The worker, DEK and checkpoints remain
with the existing native owner.

Both entries post generic progress before starting that same engine and respect
first unlock and OS user Stop. Native byte progress renews a two-minute execution
lease; a stalled transfer releases eligibility and retains its checkpoint. There
is no polling watchdog or automatic fresh UIDT from an invisible remote request.
Native completion, cancellation or removal releases the OS job/service. Transfer
completion never enables a saved Stop waiting choice.

Notifications expose only progress and an opaque operation ID. Cancel revokes
the native grant synchronously; its opaque action is saved before acknowledgement.
The same owner drains these actions before new deferred work, and acknowledges
their exact revisions only after native persistence. A delayed acknowledgement
cannot erase a newer action. Resume opens the ordinary protected Activity and
requires an eligible explicit user action. Notification content taps only open
the app; they do not restart a transfer. Actual Android constraints pause work
without claiming user cancellation.

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

The host probe also checks scheduling versus actual execution grants, stale stop
fencing, cold process incarnations and durable action acknowledgements. Transfer
Kotlin/Java and instrumentation compile against the SDK; no UIDT, dataSync,
constraint-loss or OS Stop behavior has been executed on a phone yet.
