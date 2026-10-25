# Issue 94: Android background operation

Date: 2026-10-25.
Status: Design interview in progress; implementation is not approved by this plan.
Source baseline: `v0.24.3` (`45738d1173a04c11327a99cfa6d5d203c44b6f2a`).
Related: [issue 94](https://github.com/redstone-md/mosh-flutter/issues/94),
[initial research](issue-94-background-calls.research.md).

## Accepted product decisions

The owner accepted interview questions 1, 2, 3 and 4 on 2026-10-25:

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
  without Google services.
- An untrusted intermediary may carry short encrypted wake signals, with
  self-hosting possible. This does not approve server-side message archives,
  a particular provider, a hosting location or a deployment.

These are target behavior decisions, not claims about the shipped release.
The history-key layout, authentication policy and migration are not decided.
They must not be weakened implicitly to make a background callback run.

## Wake mechanism is unresolved

The owner rejected FCM for the first implementation after comparison with
AyuGram. The Google-free wake mechanism, persistent service and dependencies
remain undecided.

The comparison must distinguish a system-assisted wake-up from an
application-owned connection. AyuGram's
[notification documentation](https://docs.ayugram.one/android/notifications/)
describes a persistent foreground connection to Telegram servers, its battery
cost, and separate FCM builds. Its quoted battery percentages are not a Mosh
baseline or a predicted result for a phone running Moss.

The design must explain what happens without Google services, after ordinary
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
| App-owned lightweight wake connection | Open | Requires a broker and a background owner; Android lifecycle and physical battery/Doze measurements remain necessary. |
| Retained direct Moss connectivity | Not selected; owner objects to retaining the full mesh in idle | Relay forwarding is verified; an economical receiver lifecycle is not. Retaining the regular node also retains its mesh work. |

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
The audit also found default Google STUN endpoints, which are separate from
FCM/Play services and require a precise no-Google policy.

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

- Wake transport, devices without Google services, persistent-connection mode
  and any gateway's trust, metadata, abuse limits and operating budget.
- Background credentials, history-key protection, notification disclosure,
  biometric policy, migration and failure behavior.
- Supported lifecycle states, network changes, reboot/first unlock and explicit
  Android Force stop; call timeout and delayed-event handling.
- Notification and call actions, one call owner, device selection, permissions
  and integration with existing audio routes and PiP.
- Quantified delivery latency, idle traffic, CPU/wakeups and battery budgets;
  acceptance on physical phones under comparable conditions.

Record a lasting architectural decision in an ADR once its alternatives and
trade-offs are settled. Proceed to runtime implementation only after the owner
confirms the completed design.
