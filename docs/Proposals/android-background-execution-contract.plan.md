# Android execution proposal for IVO-137–146

Status: proposed; no new service/permission or background guarantee ships yet.
Depends on the approved implementation of IVO-133, key access in IVO-135 and the
upstream waiting lifecycle in IVO-136. This is not a replacement for those tasks.

## Ownership

One application-owned FlutterEngine and one native installation runtime remain
the only owners. A non-exported `MoshWaitingService` keeps the installation
eligible to run; it never creates another node, database or media engine.
Move group/channel servicing into their existing native owners, alongside the
existing DM pump. Application-owned notification delivery consumes their events;
it must not depend on a mounted chat, widget polling or a visible Activity.

## Waiting execution and permissions

Use foreground service type `specialUse` on API 34+, with a manifest subtype
describing user-visible persistent encrypted peer-to-peer incoming availability
without platform push. Do not misuse `phoneCall`, `dataSync` or an arbitrary
connected-device permission for idle discovery. The remoteMessaging type was
considered; its documented messaging-task continuity purpose does not describe
all of this installation's idle call and mesh duties.

Declare `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK` and
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. The existing microphone/camera grants
remain separate and are never requested by starting waiting. No location,
exact-alarm, overlay or Google Play services permission is added for waiting.

Start waiting from foreground setup/user interaction. Show the quiet persistent
notification immediately, before key/network work. Record enabled preference
only after successful setup; absent preference means enabled after completed
setup, never before it. Denied notification or exemption grants produce explicit
limited availability instead of a success claim or repeated prompt.

A foreground service alone does not provide Doze network access. Offer the
battery exemption once with a clear user explanation and track the actual grant.
Use bounded work wake locks for processing and handover; do not silently hold an
unbounded CPU wake lock as an unmeasured substitute for economical waiting.
Actual attachment/timer survival on an unplugged sleeping phone must be measured.
If reliable carrier maintenance requires continuous wakefulness, record that
result and resolve its energy tradeoff before claiming the efficiency target.

## Intent and restart rules

- Persist Stop waiting synchronously **before** acknowledging its notification
  action. Once current calls/transfers finish, release background waiting while
  preserving off intent; stopping waiting never terminates user-started work.
- `stopWithTask=false`; ordinary task removal is not Stop waiting. Use supported
  sticky service restart for ordinary reclamation, with one serialized startup.
- A credential-encrypted `BOOT_COMPLETED` receiver starts eligible waiting only
  after first unlock; do not start capture, a call-type service or a Direct Boot
  store from boot. Recheck saved off intent and setup/key readiness first.
- Do not schedule alarms/jobs/watchdogs to revive a user-stopped application.
  Android Force stop blocks normal restart until reopening. On API 33+ Active
  apps Stop can be distinguished on later startup through the latest relevant
  ApplicationExitInfo user-requested exit. Background recovery must not override
  that exit; only an actual user reopen clears this runtime stopping condition.
- Keep OS stop distinct from the persisted app Stop waiting preference. A user
  reopen must not turn a separately saved off preference on.
- Network callbacks coalesce changes into one bounded reconnect; offline/denied
  work waits with backoff, not retry storms. Catch service-start restrictions and
  show current limited state when the user next opens Mosh.

## Incoming and ongoing calls

Use Android CallStyle notifications on supported releases and the existing
authenticated call identity/expiry/participating-device state. Immutable,
explicit PendingIntents carry the exact installation session and call ID; every
action is revalidated against current native state before changing the call.
Decline can execute without exposing chats; stale actions do nothing.

Answer opens the existing Activity's call presentation, with protected chats
covered by the independent app gate. Start microphone/camera capture only after
current offer validation, acceptance, required grants and an allowed visible
Activity transition. Promote an ongoing media service with microphone/camera
types before capture leaves the foreground. Add those type permissions only
with the call layer. No capture service starts from boot or an unsolicited hint.

Full-screen incoming presentation requires the applicable Android permission and
user/system grant; unavailable full-screen access retains an actionable call
notification rather than pretending the screen opened. Preserve existing audio
routes, ringtone, selected media owner, floating view and PiP. Native cancellation
and expiry clear presentation/actions; answering never extends chat unlock time.

## Privacy and attachments

Notification settings independently control sender/caller names and full text.
Default generic locked content omits protected text from title, body, extras,
persons, public versions and saved action payloads. Android/channel restrictions
can reduce disclosure. A preview neither unlocks chats nor marks messages read.

Apply background attachment policy at the common native download-admission
boundary for DM/group/channel: receive descriptors, do not start new automatic
clear-preview/media downloads, and preserve admitted user-started transfers.

## Approval and evidence

The new Android service/receiver/permissions, access and lifecycle channel, and
any native event/intent bridge changes need concrete review before edits.
Keep actual state separate from requested waiting, attachment readiness,
permission restrictions and known-unavailable history holders.
Physical acceptance covers supported API/OEM, unplugged Doze, locked cold
startup, task removal, ordinary reclaim, reboot, OS Stop, Force stop, permission
refusal, stale actions and concurrent linked-device answers. Emulators/CI do not
replace those conditions or battery/radio measurements.

Sources checked on 2026-10-26 through Context7 and primary Android documentation:
[service types](https://developer.android.com/develop/background-work/services/fgs/service-types),
[Doze](https://developer.android.com/training/monitoring-device-state/doze-standby),
[background starts](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).
