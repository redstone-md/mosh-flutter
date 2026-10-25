# Issue 94: Android background operation

Date: 2026-10-25.
Status: Design interview in progress; implementation is not approved by this plan.
Source baseline: `v0.24.3` (`45738d1173a04c11327a99cfa6d5d203c44b6f2a`).
Related: [issue 94](https://github.com/redstone-md/mosh-flutter/issues/94),
[initial research](issue-94-background-calls.research.md).

## Accepted product decisions

The owner accepted interview questions 1, 2, 3, 4, 5, 7, 8 and 9 on
2026-10-25, clarified the STUN boundary in question 6, and explicitly requested
opt-in message-text previews on the Android lock screen:

- Mosh app lock protects interactive access to chats. It must not prevent
  background message reception or incoming calls. A user can accept an incoming
  call without unlocking the whole Mosh interface; answering does not expose
  the chats. Cold-process key access must be designed explicitly to support
  this behavior while retaining encrypted storage and end-to-end encryption.
- The target includes incoming voice and video calls, continuation of an active
  call after minimizing, and notifications for new messages in private DMs,
  private groups and public channels. This does not change which conversation
  kinds support calls or which content is end-to-end encrypted.
- The first implementation excludes FCM. Android background operation must work
  without Google Play services; this is not a ban on using Google STUN servers.
- An untrusted intermediary may carry short encrypted wake signals, with
  self-hosting possible. This does not approve server-side message archives,
  a particular provider, a hosting location or a deployment.
- Use an explicit opt-in waiting mode in Moss, reusing its relay carrier.
  Preserve existing default behavior for desktop, gaming and SSH consumers.
  This selects the architectural direction; API and implementation details
  remain open. See [ADR 0048](../ADR/0048-android-background-waiting.md).
- Keep waiting inside the Mosh APK. It has a persistent quiet notification
  describing background availability, with a Stop waiting action.
- Target incoming activity after minimizing, screen locking, task removal and
  ordinary system process reclamation. After reboot, support begins after the
  first Android unlock. Explicit user stopping requires a manual app opening;
  it must not be treated as ordinary process reclamation and bypassed by a
  restart loop. These are acceptance targets, not universal OEM guarantees.
- Hide notification names and message text by default while Mosh app lock is
  active. Provide settings to disclose names and message text, including full
  message-text previews on the Android lock screen when explicitly enabled.
  A preview or call answer must not unlock the chat interface.

These are target behavior decisions, not claims about the shipped release.
The history-key layout, authentication policy and migration are not decided.
They must not be weakened implicitly to make a background callback run.

## Notification privacy and Android lifecycle

Mosh app lock and Android screen lock are separate states. The preview settings
must continue to apply when Mosh app lock is active; otherwise the requested
locked-screen text option would not meet the accepted behavior.
Android's system and channel notification settings can impose a stricter
disclosure policy. Mosh's setting cannot override those restrictions.

When previews are disabled, construct a generic notification without protected
names/text in its visible fields and metadata. Only marking a detailed
notification private leaves those details in its normal notification object.
When previews are enabled, use Android's supported visibility and redacted
public-version facilities as appropriate; see
[notification guidance](https://developer.android.com/develop/ui/compose/notifications/create-notification).

Keep the Android states distinct during implementation and acceptance:

| State | Accepted target |
| --- | --- |
| Home/minimized or screen locked after first Android unlock | Keep waiting and present permitted notifications/calls. |
| Task swiped from recent apps | Continue waiting; task removal alone is not an explicit Stop. |
| Process reclaimed by Android | Recover waiting through the permitted lifecycle without duplicating the runtime. |
| Reboot before first Android unlock | No incoming guarantee; credential-encrypted storage is unavailable. |
| After first Android unlock following reboot | Resume the supported background lifecycle. |
| Explicit user Stop/Force stop | Do not bypass it with automatic resurrection; manual opening is required. |

Android Active apps/Task Manager Stop terminates the whole process without
callbacks, unlike the app's Stop waiting action. Its lifecycle handling must
respect user stopping too; see
[Android user-stop behavior](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping).
The persistence and re-enable semantics of the app's own Stop waiting action
still need to be settled.

## Selected direction: Moss waiting mode

The owner chose a Moss waiting mode after comparing FCM, AyuGram and the
existing relay carrier. Its Android service, lifecycle, attachment policy,
runtime interface and dependency changes remain undecided.

The comparison must distinguish a system-assisted wake-up from an
application-owned connection. AyuGram's
[notification documentation](https://docs.ayugram.one/android/notifications/)
describes a persistent foreground connection to Telegram servers, its battery
cost, and separate FCM builds. Its quoted battery percentages are not a Mosh
baseline or a predicted result for a phone running Moss.

The design must explain what happens without Google Play services, after ordinary
process reclamation, and during Doze. A foreground service alone does not
establish an exemption from Doze network restrictions; see
[Android's guidance](https://developer.android.com/training/monitoring-device-state/doze-standby).

### AyuGram comparison

The public Android source inspected is
[`7013145676d36d82ee13c02a89f72097b7490dcd`](https://github.com/AyuGram/AyuGram4A/tree/7013145676d36d82ee13c02a89f72097b7490dcd),
dated 2023-07-28. It does not establish the behavior of the latest distributed
APK. The official documentation separately describes the distribution choices.

- [AyuPush service](https://github.com/AyuGram/AyuGram4A/blob/7013145676d36d82ee13c02a89f72097b7490dcd/TMessagesProj/src/main/java/org/telegram/messenger/NotificationsService.java#L56)
  posts an ongoing foreground notification when keep-alive is enabled.
- Its [native network owner](https://github.com/AyuGram/AyuGram4A/blob/7013145676d36d82ee13c02a89f72097b7490dcd/TMessagesProj/jni/tgnet/ConnectionsManager.cpp#L252)
  maintains a dedicated lightweight Telegram push connection, with pings around
  three minutes, while ordinary connections can be suspended. A server hint
  wakes ordinary update processing.
- [KeepAliveJob](https://github.com/AyuGram/AyuGram4A/blob/7013145676d36d82ee13c02a89f72097b7490dcd/TMessagesProj/src/main/java/org/telegram/messenger/KeepAliveJob.java#L23)
  coalesces work and ends after updates arrive or a bounded timeout.
- Its [official documentation](https://docs.ayugram.one/android/notifications/)
  acknowledges higher battery use with the persistent service and recommends
  separate FCM builds on suitable devices. Those percentages are anecdotal.

The reusable pattern is a cheap waiting channel and bounded real work. Keeping
the entire current Moss mesh active is not equivalent. AyuGram's Telegram
datacenter supplies server wake hints and retained updates; Mosh would need to
design those responsibilities explicitly if it adopts a similar wake channel.
A wake hint alone does not make an offline sender's messages available.

Mechanisms considered:

| Mechanism | Status | Idle and lifecycle trade-off |
| --- | --- | --- |
| System-assisted FCM wake | Excluded from the first implementation | Avoids an app-owned idle socket, but requires Google services and exposes delivery metadata. |
| Separate app-owned lightweight wake connection | Considered; not selected | Requires a broker and a background owner; Android lifecycle and physical battery/Doze measurements remain necessary. |
| Retained direct Moss connectivity | Not selected; owner objects to retaining the full mesh in idle | Relay forwarding is verified; an economical receiver lifecycle is not. Retaining the regular node also retains its mesh work. |
| Explicit opt-in Moss waiting mode | Selected direction; not implemented | Reuses existing relay transport with a deliberately limited receiver lifecycle; Android and energy acceptance remain required. |

The owner subsequently asked whether Android itself could be the server and
noted that AyuGram does not run its own notification servers. Keep these roles
distinct: an Android service is a local execution component; AyuGram's network
peer is Telegram's server. Hosting and any reuse of existing Moss infrastructure
remain open. Local server code does not by itself keep a sleeping phone
network-reachable or restart it after process reclamation.

### Moss feasibility check

The owner authorized checking reuse of existing Moss nodes. The
[source audit and native checks](issue-94-moss-wake.research.md) confirm that
an unchanged relay can carry encrypted traffic to a live leaf. Fifteen targeted
tests passed; a standalone C-ABI probe also verified that Stop destroys the
handle instead of preserving a receiving connection.

The pinned C API has no background/client mode or dynamic mesh suspension.
A reduced startup profile remains a candidate to measure, not a demonstrated
Android waiting policy. Reusing the carrier therefore needs explicit receiver
lifecycle/attachment work; it does not automatically require a new hosted server.
The audit also found default Google STUN endpoints. The owner explicitly
permits these: address discovery is outside the excluded event-delivery role
of FCM. No STUN-provider removal is part of this design.

## Existing boundaries

- [ADR 0034](../ADR/0034-android-linked-text-dm.md) deliberately gates cold-start
  history access on user authentication and makes no background delivery claim.
  Warm locked operation and cold locked operation need separate checks.
- [ADR 0044](../ADR/0044-native-call-media-over-moss.md) keeps the media owner
  native and media transport on Moss. A background owner must reuse the
  installation's existing runtime instead of creating another node.
- Existing incoming presentation depends on Flutter snapshots and a mounted
  widget. Receiving a native call offer does not itself ensure a visible alert
  while UI polling is paused.
- Android battery and network usage still need physical-phone measurement.
  Earlier desktop traffic reports do not establish Android drain.

## Remaining design questions

- Moss waiting lifecycle/interface, attachment selection and any intermediary's
  trust, metadata, abuse limits and operating budget.
- Background credentials, history-key protection, biometric policy, migration
  and failure behavior; plaintext previews require real background key access.
- Implementation of the accepted lifecycle states, network changes, persistent
  user-stop handling, app Stop waiting/re-enable semantics, call expiry and
  delayed-event handling.
- Notification and call actions, one call owner, device selection, permissions
  and integration with existing audio routes and PiP.
- Quantified delivery latency, idle traffic, CPU/wakeups and battery budgets;
  acceptance on physical phones under comparable conditions.

Record a lasting architectural decision in an ADR once its alternatives and
trade-offs are settled. Proceed to runtime implementation only after the owner
confirms the completed design.
