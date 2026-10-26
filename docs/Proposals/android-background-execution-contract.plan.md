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

Reuse existing notification permissions/settings, `ic_stat_mosh`, channel IDs,
ringtone and non-Android delivery. The installed `flutter_local_notifications`
22.2.0 already supports channels, actions and foreground services, but its public
Android styles omit CallStyle and its publication has no Mosh-native access-state
check at the final OS boundary. Keep the Android-specific publisher small for
those requirements; do not fork the plugin or build a second general-purpose
notification system. Once that owner attaches, the old Android widget publisher
must yield, so one incoming call cannot produce competing notifications.

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
explicit PendingIntents carry an opaque capability bound to the exact
installation session and call ID; every action is revalidated against current
native state before changing the call.
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

Answer uses an immutable Activity PendingIntent directly, not a receiver/service
that then launches UI. Bind each action to a random 128-bit one-use capability
held in encrypted local state, in addition to the exact call/revision/action.
The exported launcher must reject a forged intent containing only a known call
ID. Decline/hangup may use non-exported receivers. No message text, caller name,
conversation ID or call key belongs in generic notification extras; OS actions
carry only the opaque capability. Revalidate after initialization and before
acceptance/capture; an expired or replaced call consumes no newer call's action.

## Proposed native bridge and durable delivery

These additions require approval. Reuse existing conversation/call identifiers,
snapshots, history codecs and native runtime owners; do not add a second store.
Android attaches the application owner after a valid DEK is injected. Desktop
does not start this owner or acquire new background loops by default.

| API | Exact scope |
| --- | --- |
| `set_background_execution(interactive: bool, waiting_enabled: bool)` | Idempotently update desired execution and return actual BackgroundStatus |
| `background_status()` | Current requested/actual mode, attachment reachability and active user-work state |
| `watch_background_changes(StreamSink<u64>)` | One replaceable subscriber; coalesced revision hints, never success receipts |
| `pending_background_notifications(limit: u32)` | Read at most 16 pending typed notifications from encrypted storage |
| `ack_background_notification(id: String, revision: u64)` | Acknowledge only the exact successfully posted revision |
| `apply_background_call_action(capability: String)` | Revalidate/consume the exact call action; report applied, stale or unavailable |

`interactive` means an actually resumed Activity, independently of chat unlock;
it is not inferred from a mounted widget or an incoming notification. Accepted
calls and admitted user transfers are separate native facts and may require
active mode with no visible Activity. Waiting/off intent cannot end that work.

BackgroundStatus uses typed active/waiting/offline/unsupported states, plus
actual carrier reachability and current calls/user-started transfers. Platform
notification/exemption grants remain actual Android facts, not guesses in Rust.
Notification entries contain an opaque ID/revision, typed conversation target,
original occurrence or exact call identity, current call phase/expiry, optional
display text and an action-specific capability. They contain no secret keys.
Full local text may cross the app's own bridge; the Android publisher performs
the final privacy reduction against the current native access state immediately
before constructing OS fields. It must not trust a stale Dart lock snapshot.

Add one encrypted `background_delivery` table, separate from history-recovery
tables. Typed keys hold per-conversation pending summaries, exact call-action
capabilities/revisions and notification acceptance watermarks. Reuse the existing
DEK and transaction helpers. Do not serialize OS actions into readable history.
No table row is a license to accept an unauthenticated conversation event.

Queue a notification only with a successful durable incoming-message/import or
authenticated call-state transition. Coalesce pending message summaries per
conversation while preserving unread content; never mark read. The stream only
signals that durable work changed, so a slow UI cannot require unbounded in-memory
message copies. Read bounded batches from storage and yield to live user work.
Failure to post due to permission/OS refusal is not acknowledged as delivery.
Replaying an unacknowledged revision uses the same OS notification ID with
only-alert-once behavior; no duplicate receipt or fresh obsolete call ring.

On upgrade establish the initial watermark from existing durable history;
opening the old store must not notify every old message as new. Preserve pending
state across reclamation. Current action state and expiry win over persisted
notification buttons. Clearing or previewing a notification does not mark read.

Service work is driven by native owner changes, not full-history widget polling.
Use the existing DM pump and add independent draining/maintenance to group and
channel owners, with bounded work and no nested cross-runtime locks. A rejected
subscriber or unsupported transport reports actual state; it does not create a
second node. Foreground UI, waiting, an accepted call or a user-started transfer
may keep the shared owner active. Stop waiting remains off when that work ends.

## Platform adapter and long transfers

Proposed application-owned channel: `app.mosh.mosh/waiting`.
Methods: `status`, `enable`, `stop`, `requestBatteryExemption`,
`publishNotification`, `setUserWork` and `setNotificationPolicy`.
Inputs are typed maps with bounded strings and exact opaque IDs/revisions.
`enable` requires a permitted foreground/user-entry path and completed setup;
`stop` commits off intent before acknowledging. `setUserWork` mirrors verified
native call/transfer state rather than inventing media ownership. Publication
returns posted/blocked/failed; the last two never advance the durable watermark.
Privacy preferences independently cover names and text and default to hiding
both while app lock is active. Their synchronous native read is authoritative
when publishing; permission/channel restrictions can limit disclosure further.

User-started transfers use Android 14+ user-initiated data transfer jobs with
their progress notification, scheduled from the actual foreground user action.
Add `RUN_USER_INITIATED_JOBS` and a non-exported JobService protected by
`BIND_JOB_SERVICE`. Existing transfer IDs/manifests remain the work identity;
the job keeps the same native transfer running rather than creating another
downloader. On Android 8–13 use the foreground data-transfer service path.
Do not misuse idle waiting's specialUse category for an independently typed
transfer or ignore modern dataSync execution quotas. OS interruption preserves
durable transfer state and truthful progress, without setting waiting back on.
No new automatic media/preview download is admitted by these execution rights.

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
Also test notification replay/ack races, forged exported-Activity call intents,
subscriber replacement, native-state privacy races, outbox refusal and no flood
of upgrade-time history. Exercise actual user-started transfers through Stop
waiting and supported job/service interruption without a second transfer owner.

Sources checked on 2026-10-26 through Context7 and primary Android documentation:
[service types](https://developer.android.com/develop/background-work/services/fgs/service-types),
[Doze](https://developer.android.com/training/monitoring-device-state/doze-standby),
[background starts](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).
Additional primary sources:
[notification trampolines](https://developer.android.com/about/versions/12/behavior-changes-12#notification-trampolines),
[user-initiated transfers](https://developer.android.com/develop/background-work/background-tasks/uidt),
[dataSync time limits](https://developer.android.com/develop/background-work/services/fgs/timeout).
