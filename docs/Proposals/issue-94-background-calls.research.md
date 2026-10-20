# Issue 94: idle resource use and Android incoming calls

Research date: 2026-10-20. Source baseline:
`6f73fcc18fe43e3fecf9e945e9863fc66af69ac1` (`v0.24.1`).
[Issue 94](https://github.com/redstone-md/mosh-flutter/issues/94).
This is research, not an approved implementation or a changed runtime contract.

The reported excessive idle network use is on **desktop**, possibly with chats
open. The reported 100–150 figure has no captured measurement window or verified
unit here. Android network consumption is **not confirmed**. Android background
incoming calls and battery/network efficiency remain requirements to measure.

## Desktop: established source facts

The checked-in Moss revision is `0effb8bb2cd318d2fb516cd2689083daaa5a1917`.
`scripts/moss-prepare.mjs:54` builds that checkout into the native library. The
following are source facts at this baseline, not measured traffic contributions.

| Mechanism | Evidence and implication |
| --- | --- |
| UI reads every second | [auto_poll_provider.dart:15](../../lib/src/state/auto_poll_provider.dart#L15) refreshes chat names and all three conversation lists. Its list listener also invalidates the open conversation's snapshot at `:34`. [ForegroundPoller:12](../../lib/src/platform/foreground_poller.dart#L12) applies lifecycle pausing only to Android; desktop keeps its timer when hidden. |
| Reads also drive the protocol | [DM actions:131](../../mosh-core/src/private_dm_runtime/actions.rs#L131) calls `drain_inbound()` for both snapshot and list. The open conversation's [view listener:248](../../lib/src/features/conversation/conversation_screen.dart#L248) calls `markViewed()`, whose [native entry:45](../../mosh-core/src/private_dm_runtime/actions.rs#L45) also drains before checking the receipts toggle. [Service:79](../../mosh-core/src/private_dm_runtime/service.rs#L79) ticks every DM, not just the selected conversation. |
| Independent workers already exist | [DM worker:180](../../mosh-core/src/api/private_dm.rs#L180) runs every 500 ms. [Device-link worker:15](../../mosh-core/src/api/device_link.rs#L15) does the same. [Chat-name snapshot:33](../../mosh-core/src/device_link/runtime/names.rs#L33) additionally calls device-link `service()`. These owners have no app visibility policy; their work is additional to UI-driven reads. |
| Lists return full histories | [DM list:142](../../mosh-core/src/private_dm_runtime/actions.rs#L142) creates a complete snapshot per visible session; [snapshot:11](../../mosh-core/src/private_dm_runtime/snapshot.rs#L11) rebuilds message views, attachments and mesh information. [Group list:324](../../mosh-core/src/private_group_runtime.rs#L324) and [channel list:218](../../mosh-core/src/channel_runtime.rs#L218) likewise return complete snapshots. This is local bridge/CPU/allocation work, not itself WAN traffic. |
| Repeated device identity | [Device pump:72](../../mosh-core/src/private_dm_runtime/devices/runtime.rs#L72) runs at a two-second floor. For each eligible joined DM it invokes [publish_identity_claim:86](../../mosh-core/src/private_dm_runtime/devices/identity_session.rs#L86): create a claim, freshly encrypt it and send it even without a changed claim. The receiver at `:136` marks the record dirty on acceptance. Cost grows with sessions, roster and recipients; byte/CPU contribution is unmeasured. |
| Recovery probes while up to date | [Recovery:119](../../mosh-core/src/private_dm_runtime/devices/recovery/mod.rs#L119) periodically creates a new round/request and saves membership when no source is selected. Its probe floor is five seconds, serviced by the two-second device pump. [Probe response:19](../../mosh-core/src/private_dm_runtime/devices/recovery/source.rs#L19) hashes history keys for the manifest. [Offer handling:31](../../mosh-core/src/private_dm_runtime/devices/recovery/import.rs#L31) compares manifests and avoids a full history import when already equal/observed. These are repeated probes and persistence, not proof of repeated full-history downloads. |
| Other periodic metadata | [Deletion sync:159](../../mosh-core/src/private_dm_runtime/deletion.rs#L159) requests a digest every two seconds when shared deletion records exist. [PLUS schedule:19](../../mosh-core/src/plus/transport.rs#L19) permits metadata every five seconds; [DM PLUS sync:4](../../mosh-core/src/private_dm_runtime/plus.rs#L4) constructs and sends it if the owner yields a frame. [Production frame:24](../../mosh-core/src/plus/mainnet_peers.rs#L24) skips accounts that never exposed their badge. A disabled checkout is not evidence that all peer metadata is idle. |
| Eager discovery configuration | [Mosh config:21](../../mosh-core/src/moss_ffi/config.rs#L21) sets announce 15 s, gossip heartbeat 250 ms and LAN discovery enabled, with UPnP/NAT-PMP/PCP and eight hole-punch attempts. [Moss defaults:272](../../moss/internal/mesh/config.go#L272) are announce 120 s, heartbeat 1000 ms and max peers 200; Mosh leaves the peer limit at that default. The configured cadences warrant measurement; a 250 ms maintenance tick does not mean every peer receives a packet each tick. |
| Client can relay others' traffic | Mosh supplies no distinct client relay-role policy. [Moss readiness:225](../../moss/internal/mesh/node_dispatch_bootstrap.go#L225), [promotion policy:11](../../moss/internal/nat/supernode.go#L11) and [defaults:293](../../moss/internal/mesh/config.go#L293) permit eligible publicly reachable Public/FullCone nodes to become supernodes after 300 s, subject to capacity/cooldown. [Relay handling:70](../../moss/internal/mesh/node_relay_control.go#L70) can establish a transit route. An idle Mosh UI therefore does not establish an idle network node; whether the reporting desktop actually relays anything is unknown. |

### Existing protections and measurement pitfalls

- [Shared resources:40](../../mosh-core/src/api/shared_runtime.rs#L40) and
  [SharedMossNode:89](../../mosh-core/src/shared_node.rs#L89) create/reuse one node.
  Opening another chat adds room/session work; the inspected application path
  does not start a separate node for each open chat.
- [Peer connection:159](../../mosh-core/src/private_dm_runtime/session_transport.rs#L159)
  registers a known peer once per ID. Hello/handshake work has cadence guards
  (`session_transport.rs:239`; `private_dm_runtime.rs:56`: 2 s handshake and
  10 s keepalive). UI reads cannot automatically multiply every outbound timer.
- [Moss maintenance:509](../../moss/internal/mesh/node_maintenance.go#L509)
  already separates connection upkeep from the fast gossip heartbeat. Its
  [pong handler:214](../../moss/internal/mesh/node_maintenance.go#L214) retains the
  timestamp enforcing the 15 s probe floor. The old ping-every-tick defect
  described in the source comment is already fixed in the inspected revision.
- Read receipts skip already sent message IDs in
  [typing.rs:132](../../mosh-core/src/private_dm_runtime/typing.rs#L132).
  Repeated `markViewed()` still costs a runtime pass, but is not evidence of
  resending every receipt on every read.
- [Mosh mesh DTO:45](../../mosh-core/src/conversation/mesh.rs#L45) already exposes
  `supernode_ready`, relay session/route counts, NAT type and peer details.
  These can distinguish consuming a relay from providing transit for others.
- Moss already has [debug throughput:276](../../moss/internal/mesh/node_debug_metrics.go#L276)
  and [ciphertext counters:66](../../moss/internal/transport/conn.go#L66).
  However, [sessionByteTotals:67](../../moss/internal/mesh/node_stat.go#L67)
  sums only **currently live sessions**: its aggregate can fall when one closes.
  These counters exclude tracker/STUN and other traffic outside established
  session ciphertext, and do not equal OS wire-byte totals. Use process-level
  capture/accounting as the byte source; correlate the existing metrics with it.
- [Host-requested recording:43](../../mosh-core/src/moss_ffi/config.rs#L43)
  enables existing bounded Moss diagnostics via `MOSH_DEBUG_RECORD_DIR`.
  Diagnostics can contain peer IDs, addresses and a tokenized local debugger
  URL; keep raw captures local and publish aggregate attribution only.

## Investigation order and measurement matrix

This table ranks **checks**, not measured hotspots. No CPU, byte-rate or battery
profile from the reporting devices was available. It is not a claim that the
first row is the root cause.

| Priority | Candidate | Distinguishing observation |
| --- | --- | --- |
| 1 | Transit/mesh traffic unrelated to user interaction | Correlate process RX/TX with `supernode_ready`, relay routes/sessions, peer count and connections unrelated to the contact. Compare before/after the 300 s promotion threshold. |
| 2 | Per-conversation metadata/recovery | Attribute outbound identity, recovery, deletion and PLUS frame counts/bytes; compare the same idle account with different saved-session/linked-device counts and reachable/unreachable peers. |
| 3 | Discovery and connection churn | Separate tracker/LAN/STUN, dial attempts and session open/close from application/control traffic. Measure steady state separately from startup/reconnect; use the configured 15 s announce as a lead, not proof of volume. |
| 4 | UI/bridge CPU amplified by an open chat | Compare list-only, open DM, open group/channel and minimized states. Record native tick/DB-write counts and snapshot bytes/time; distinguish local FRB serialization from actual network bytes. |

Use the same release/build, account, network, contacts and peer state for every UI
comparison. Capture at least a ten-minute steady idle window after startup has
settled, so possible relay promotion is visible. Record absolute process RX/TX
bytes and elapsed time; derive B/s and Mbit/s explicitly. Preserve session events
across churn rather than differencing a live-session sum as a lifetime counter.

The existing [idlepair harness](../../moss/cmd/idlepair/main.go) can isolate a
Moss pair, and `mosh-probe` exercises actual native DM paths. Neither alone
reproduces the complete desktop widget/provider workload or the public mesh.
Reuse these seams for controlled comparisons, then confirm against the reporting
desktop. No harness, profiler, kernel setting or shipping timer was changed here.

The first implementation should add the minimum missing **aggregate attribution**
at existing transport/service boundaries, then address the measured dominant
source. Reuse counters and the shared node; do not build a second diagnostics
system. Prefer scheduling dirty/deadline work from one runtime owner and making
snapshot reads independent of protocol progress. Group/channel progress currently
depends on their `drain_inbound()` entry points, so simply removing those calls or
stopping all polling would break delivery/sync. Slim list DTOs, new event streams
or a Moss client relay-role API would change contracts and require an approved
design before implementation. Timer-only reductions do not establish a fix.

## Android: established source facts

| Boundary | Current behavior and source |
| --- | --- |
| App entry | `android/app/src/main/kotlin/app/mosh/mosh/MainActivity.kt:13` initializes native media, permission UI, ringtone and PiP from the Activity's Flutter engine. Its cleanup disposes the latter three at `:60`. |
| Platform declarations | `android/app/src/main/AndroidManifest.xml:1` declares network, microphone, camera and a PiP Activity. The app source declares no calling service, push receiver, Telecom integration, FGS permissions or full-screen incoming-call Activity. The final merged manifest also includes dependency declarations; this is not a claim that all notification permission declarations are absent. |
| Hidden UI | `lib/src/platform/foreground_poller.dart:35` stops Android UI timers when hidden/paused/detached; resume refreshes immediately. `lib/src/state/auto_poll_provider.dart:55` refreshes conversation lists through that poller. |
| Incoming presentation | `lib/src/state/voice_call_session_provider.dart:16` selects calls from DM-list snapshots. `lib/src/state/voice_call_orchestrator_provider.dart:164` derives ringing from those snapshots. `lib/src/features/voice_call/voice_call_layer.dart:71` posts the OS alert from a mounted widget. There is no separate wake-driven incoming-call owner. |
| Native runtime | `mosh-core/src/private_dm_runtime/service.rs:5` services signaling independently of UI reads. `mosh-core/src/native_call/mod.rs:32` owns media in Rust, with its own worker. This separates media from widgets, but does not confer Android background execution rights or survive process death. |
| Alert details | `lib/src/features/voice_call/call_notification_details.dart:5` configures an ordinary high-priority call-category notification with no second notification sound. `voice_call_layer.dart:189` supplies no Answer/Decline actions. Notification permission/init already exists in `lib/src/state/notifications_provider.dart:65`. |
| Ringing | `android/app/src/main/kotlin/app/mosh/mosh/MoshRingtone.kt:41` reuses the WAV assets, ringer mode, audio attributes/focus and a bounded timeout. It is reached through an engine MethodChannel, not an independently started service. |
| Existing PiP | `android/app/src/main/kotlin/app/mosh/mosh/MoshCallPresentation.kt:57` enters PiP for an existing video call. `:94` signals termination when PiP closes. It does not register a dormant app to receive new calls. |
| Audio routes | `android/app/src/main/kotlin/app/mosh/mosh/MoshCallAudio.kt:60` owns focus, communication mode and `setCommunicationDevice`; teardown restores them at `:91`. A Telecom adoption must reconcile this ownership. |
| Presentation polling | `lib/src/features/voice_call/native_call_session.dart:50` starts a 16 ms presentation poll only when a call session is prepared; `:137` also reads state at 250 ms intervals. This is an active/prepared-call concern, not evidence of an idle network flood. |

An incoming offer can therefore reach an already running native DM runtime while
hidden without making the snapshot-driven ringtone/notification refresh. That is
a source-level consequence, not a measured explanation for every missed call.
Leaving all UI polling active would not solve process death or Doze.

### Cold start and locked storage are a separate blocker

`lib/main.dart:156` explicitly waits for Activity `resumed` before
`initMobileDek()` and mounting the ordinary app. Its comment records a previous
locked-background Keystore recovery crash; removing the guard is not a fix.
`lib/src/platform/mobile_dek.dart:34` uses biometric/device-credential-gated DEK
release. [ADR 0011](../ADR/0011-secure-storage-and-threat-model.md) and
[ADR 0034](../ADR/0034-android-linked-text-dm.md) make this deliberate.

A fresh background process cannot silently open the existing encrypted DM state
through this startup path. Warm-process background operation and cold-process
waking need distinct acceptance scenarios. A locked-state wake handler must not
pretend it authenticated an MLS offer using keys it cannot access.

Proposed policy choices, requiring an explicit security decision:

- Keep conversation storage locked; show a generic alert from an authenticated,
  separately provisioned, narrowly scoped wake capability, then unlock and
  validate the actual pending call before answering. Define replay/expiry,
  revocation, rate limits and caller privacy for that capability.
- If answering without unlocking is required, design limited background call
  credentials/state deliberately. This is a storage/security extension, not a
  permission toggle or a reason to make the history DEK unauthenticated.

## Android platform constraints, verified in official documentation

Context7 was consulted for Android Developers and Firebase. Broad Android
reference search results did not cover every restriction, so the relevant
official guide pages were checked directly as well.

- **Doze:** network, jobs and normal alarms are deferred. WorkManager is not a
  realtime incoming-call transport. Android recommends the shared FCM connection
  rather than each app holding its own persistent connection; high-priority,
  user-visible pushes can grant a short execution/network window. A foreground
  service must not exist merely to prevent idle classification.
  [Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby).
- **Starting work is not permission to capture:** targeting Android 12+ restricts
  background FGS starts. A delivered high-priority FCM message is an exemption,
  but can be downgraded. Android 14+ additionally checks while-in-use camera and
  microphone permissions at service creation; the FCM exemption alone does not
  satisfy them. User interaction with a notification has a separate exemption.
  Design ringing without opening camera/microphone; acquire capture through a
  permitted, explicit answer path.
  [Background FGS restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).
- **Declare real work:** Android 14+ needs appropriate FGS types/permissions.
  `phoneCall` requires `MANAGE_OWN_CALLS` or the dialer role; camera/microphone
  have their own prerequisites. Android 15+ restricts starting phone-call FGS
  from boot. Do not label a permanent discovery loop as an ongoing call.
  [FGS types](https://developer.android.com/develop/background-work/services/fgs/service-types).
- **Established call integration:** Core-Telecom provides platform call lifecycle,
  remote controls and audio endpoints. Its guide hosts `CallsManager` in a
  foreground service and requires a timely call notification. It explicitly
  warns against using `AudioManager.setCommunicationDevice`/Bluetooth SCO routing
  alongside Telecom's endpoint owner. Reuse the media engine, migrate platform
  routing behind its existing boundary, and avoid two competing owners.
  [Core-Telecom](https://developer.android.com/develop/connectivity/telecom/voip-app/telecom).
- **System call UI:** CallStyle supplies incoming Answer/Decline and ongoing
  Hang-up actions backed by PendingIntents. Existing Mosh notifications have
  neither this lifecycle nor these actions.
  [CallStyle](https://developer.android.com/develop/ui/compose/notifications/call-style).
  Notification permission denial needs an explicit supported behavior; the
  self-managed-call exemption has configuration requirements and does not follow
  merely from setting category `call`.
  [Notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission).
- **Full-screen UI is conditional:** Android 14 limits default full-screen intent
  access to calling/alarm use cases and exposes an access check. Do not assume
  every notification may force a background Activity to the front.
  [Full-screen intent restrictions](https://developer.android.com/about/versions/14/behavior-changes-14#secure-fsi).
- **Push is a bounded hint:** FCM high priority is for time-sensitive visible
  notifications. The handler has only a short processing window; waiting there
  for mesh discovery or a long history import is unsafe. Missing visible alerts
  can lead to deprioritization. Use expiry and idempotence; a delayed wake must
  not revive an ended call.
  [FCM priority](https://firebase.google.com/docs/cloud-messaging/android-message-priority).
  Sending also requires a trusted server environment; sender credentials cannot
  ship in desktop/Android clients.
  [FCM server environment](https://firebase.google.com/docs/cloud-messaging/server-environment).

### Hard limits

OS process reclamation, removing a task, screen locking, reboot, and an explicit
**Settings → Force stop** are different states. Force stop is not a recoverable
delivery target: FCM documents that Android users must reopen the app afterward.
[FCM receive conditions](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
Android 15 also cancels PendingIntents in the stopped state; recovery requires
user action. Do not promise calls after force stop.
[Package stopped state](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state).
Do not conflate a locked, previously unlocked phone with Direct Boot before the
first unlock; no before-first-unlock storage design is approved here.

## Established-product reference

Signal Android source at `c56038f39c4cc0280e49a346ebabbc15edb2dadb`
separates push receipt from actual message retrieval: `FcmReceiveService` checks
delivered priority, attempts the permitted service start and enqueues a fetch.
Its `FcmFetchManager` bounds/coalesces work, drains and processes the WebSocket,
and stops temporary services after outstanding work ends.
[Push entry](https://github.com/signalapp/Signal-Android/blob/c56038f39c4cc0280e49a346ebabbc15edb2dadb/app/src/main/java/org/thoughtcrime/securesms/gcm/FcmReceiveService.java#L81),
[fetch owner](https://github.com/signalapp/Signal-Android/blob/c56038f39c4cc0280e49a346ebabbc15edb2dadb/app/src/main/java/org/thoughtcrime/securesms/gcm/FcmFetchManager.kt#L114).
The reusable pattern is a wake hint followed by bounded authoritative processing;
this inspection does not establish Signal's call/key policy or justify copying it
over Mosh's user-presence gate.

## Architecture options — proposals, not decisions

| Option | Strength | Cost / limit |
| --- | --- | --- |
| Provider wake + temporary call service | Let Android's shared push connection sleep between real events; call service lives for ringing/active calls, while MLS and media remain in the existing Rust/Moss owner. | Requires a wake broker, device registration/token rotation, abuse limits and metadata/privacy policy. FCM depends on compatible Google services. Locked-state authentication and capture still need the design above. |
| Permanent application-owned connection/FGS | Reuses Moss directly without introducing a push provider. | Retains connectivity, discovery and process work at idle; Android Doze/start rules and OEM behavior still apply. A permanent FGS is not a general exemption or a guarantee after process death/force stop. It conflicts with the battery goal as a default unless measurements establish a justified supported mode. |

Recommended candidate to investigate: a provider-neutral **wake boundary**, with
FCM as a possible adapter, plus platform call ownership through Core-Telecom.
The wake broker must never authorize a Mosh call, become the media relay, hold
MLS/history keys or replace the existing selected-device protocol. Registration,
recipient capabilities, expiry, cancellation and retries need an authenticated,
bounded contract. It must work with the peer's desktop offline, not require an
always-online linked desktop as a surrogate phone server.

This is an architectural choice: [ADR 0044](../ADR/0044-native-call-media-over-moss.md)
currently keeps native media over Moss and avoids another mandatory server.
Optional wake assistance must preserve direct foreground calls when unavailable;
making it mandatory or changing storage/protocol/dependencies needs a plan/ADR
decision before implementation. Provider-free devices need an honestly stated
support boundary rather than hidden permanent polling.

## Reusable pieces and smallest end-to-end order

1. Measure desktop idle traffic separately from Android. Record RX/TX bytes per
   second, duration, process, peer/room counts and open/closed chat state before
   attributing consumption to discovery. Establish an Android baseline on a phone.
2. Keep existing authenticated MLS call state, account occupancy and selected
   device semantics ([ADR 0043](../ADR/0043-one-device-per-user-in-a-call.md)).
   Preserve the Rust `native_call::Hub`, RingRTC engine, current PiP/video view,
   bounded ringtone, permission refusals and call-bound stale-command guards.
3. Choose locked-state behavior and wake provider/service ownership. Define one
   runtime shared by Activity/service, with platform initialization independent of
   Activity recreation. Choose a supervised retained engine or a native service
   bridge deliberately; do not construct another Moss node for the background.
4. Prove one current protocol call end to end: warm unlocked installation →
   Home/lock → authenticated incoming → system Answer/Decline → same call media
   owner → Hang-up/cleanup. Prove ongoing voice survives lock without opening
   a camera; add video/PiP using the same call and explicit camera choice.
5. Add cold process wake through the decided limited handler. Show a prompt alert
   within its allowed window; unlock only when required; validate the live MLS
   call before media. Bound reconnect time, stale offers and all terminal paths.
6. Suspend idle background mesh work only once the chosen wake path actually
   works. Resume/recover through existing durability. Measure the same idle and
   active-call cases again; optimize polling/transport from evidence, not by
   increasing timers until calls silently stop arriving.

## Verification and measurement limits

This research changes no runtime code, permissions, dependencies or schemas.
Source inspection and official docs do not prove a device battery/network rate
or delivery latency. No physical Android phone or desktop packet capture was
available for this investigation, and no runtime performance claims are made.

Acceptance needs paired desktop/phone calls, screen-on background, screen lock,
forced Doze, Wi-Fi/mobile transitions, ordinary process reclamation, duplicate
and late wakes, revoked linked devices, notification denial, audio/camera denial,
Bluetooth, and return from PiP. Treat explicit Force stop as the documented
unavailable case; after reboot test both before and after first unlock separately.

Measure idle and active call CPU, bytes over time, wakeups/wakelocks and battery
on unplugged hardware with the same contacts/network. Use UID-level counters and
Android Batterystats/Perfetto as appropriate; report measurement windows and
versions. Emulator/service unit tests cannot establish phone radio drain, OEM
background reliability, thermal behavior or physical camera/audio continuity.
