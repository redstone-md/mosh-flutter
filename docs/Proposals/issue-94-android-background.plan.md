# Issue 94: Android background operation

Date: 2026-10-25.
Status: Product interview complete; specification published. This change does
not implement runtime behavior.
Source baseline: `v0.24.3` (`45738d1173a04c11327a99cfa6d5d203c44b6f2a`).
Specification: [issue 100](https://github.com/redstone-md/mosh-flutter/issues/100)
and its [repository copy](android-background.spec.md).
Related: [issue 94](https://github.com/redstone-md/mosh-flutter/issues/94),
[initial research](issue-94-background-calls.research.md).

## Accepted product decisions

The owner accepted interview questions 1, 2, 3, 4, 5, 7, 8 and 9 on
2026-10-25, clarified the STUN boundary in question 6, and explicitly requested
opt-in message-text previews on the Android lock screen:

Questions 10 through 12 were accepted on 2026-10-26.
For questions 13 through 15 on the same date, the owner required complete
missed-history recovery in this slice, added configurable app-lock delay, and
accepted the background attachment policy below.
Questions 16 and 17 were accepted on 2026-10-26. For question 18, the owner
accepted the timer choices and default, but required Android screen locking to
obey the same timer instead of immediately locking Mosh. Telegram's Android
implementation is the requested comparison for the timing behavior.

- Mosh app lock protects interactive access to chats. It must not prevent
  background message reception or incoming calls. A user can accept an incoming
  call without unlocking the whole Mosh interface; answering does not expose
  the chats. Cold-process key access must be designed explicitly to support
  this behavior while retaining encrypted storage and end-to-end encryption.
- The target includes incoming voice and video calls, continuation of an active
  call after minimizing, and notifications for new messages in private DMs,
  private groups and public channels. This does not change which conversation
  kinds support calls or which content is end-to-end encrypted.
- Include recovery of messages missed while offline for private DMs, private
  groups and public channels in the same completed slice. Group/channel history
  recovery must not be deferred to a later slice or represented as complete
  merely because live background notifications work. Recover from available
  authorized holders, including someone other than the original author. Wait
  and retry when no holder is reachable; do not add a central message archive.
  Data absent from every remaining copy cannot be reconstructed.
- Private-group history starts at joining. Do not serve new history to removed
  members or reveal the interval between leaving/removal and rejoining.
  Ordinary offline periods do not end membership and must be recoverable.
  Public-channel recovery can include all available retained history.
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
- After the first Android unlock following reboot, allow the background process
  to obtain the database key without a new biometric prompt, including after
  ordinary process reclamation and while the screen is locked again. Keep
  encrypted storage and Keystore protection; biometric authentication gates
  interactive chat access rather than each background database-key use. This
  deliberately changes the biometric key-release policy; see
  [ADR 0049](../ADR/0049-android-background-key-access.md).
- Offer the background battery-optimization exemption once. On refusal, expose
  limited background availability without repeated prompts or a false guarantee
  that the phone remains reachable.
- Initially enable waiting after setup. The app's Stop waiting action persists
  the disabled state until explicit re-enabling, including across restarts.
  It does not end an active call.
- When app lock is enabled, re-lock interactive chat access after the configured
  delay following backgrounding or Android screen locking. Offer immediate,
  1, 5, 10 and 30 minute choices, defaulting to 1 minute. Android screen locking
  obeys that delay too; it must not independently force immediate Mosh lock.
  Temporary permission dialogs and file pickers must not count as leaving Mosh.
  Incoming call answer and call controls remain separate from chat unlocking.
- Waiting receives text, call signaling and attachment offers without starting
  automatic media or clear-preview downloads. Continue transfers already
  initiated by the user, including after Stop waiting; disable waiting after
  active user work ends without silently re-enabling its saved preference.

These are target behavior decisions, not claims about the shipped release.
The Android key-release and configurable UI-lock policies are now explicit;
the concrete storage mechanism, safe migration and lifecycle timing mechanics
still need design. No existing key or history may be replaced merely because
a background startup cannot open it.

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
The app's Stop waiting action instead persists a disabled preference before
stopping waiting; it stays disabled until the user explicitly re-enables it.
Opening the app after an OS Force stop must not erase that separate preference.

### Telegram auto-lock reference

Inspected the official Android source at
[`3de37c8cfb039452be7398909461da6288babf15`](https://github.com/DrKLO/Telegram/commit/3de37c8cfb039452be7398909461da6288babf15)
(2026-10-25, Telegram 13.1.1). This establishes source behavior, not a physical
test of a particular installed APK.

- [ScreenReceiver](https://github.com/DrKLO/Telegram/blob/3de37c8cfb039452be7398909461da6288babf15/TMessagesProj/src/main/java/org/telegram/messenger/ScreenReceiver.java#L20)
  reports screen state without directly forcing app lock.
- [LaunchActivity](https://github.com/DrKLO/Telegram/blob/3de37c8cfb039452be7398909461da6288babf15/TMessagesProj/src/main/java/org/telegram/ui/LaunchActivity.java#L8254)
  uses the same pause/resume lock check for backgrounding and screen changes.
  It records elapsed time and rechecks the interval on return, rather than
  depending on a delayed callback firing while asleep.
- Telegram's interval options/default differ from the accepted Mosh choices;
  reuse its timing pattern rather than silently replacing Mosh's settings.

For Mosh, use one grace deadline from the transition out of interactive use.
Locking an already-backgrounded phone must neither shorten nor restart it.
Reopening chats before expiry needs no fresh authentication; after expiry,
authenticate before exposing chat content. A notification, background history
sync or call answer must not extend the chat-unlock deadline. Check elapsed
time again on return so sleeping cannot postpone expiry. Preserve a valid
deadline across ordinary process reclamation; an unverifiable deadline must
not bypass authentication. These are timing requirements, not a selected
storage API or an approval for a new authentication dependency.

## Selected direction: Moss waiting mode

The owner chose a Moss waiting mode after comparing FCM, AyuGram and the
existing relay carrier. Its Android service, lifecycle, relay attachment
selection, runtime interface and dependency changes remain undecided.

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

- [ADR 0034](../ADR/0034-android-linked-text-dm.md) describes the shipped cold-start
  biometric key gate and makes no background delivery claim. ADR 0049 changes
  the target policy, not the currently shipped implementation. Warm locked
  operation and cold locked operation need separate checks.
- [ADR 0044](../ADR/0044-native-call-media-over-moss.md) keeps the media owner
  native and media transport on Moss. A background owner must reuse the
  installation's existing runtime instead of creating another node.
- Existing incoming presentation depends on Flutter snapshots and a mounted
  widget. Receiving a native call offer does not itself ensure a visible alert
  while UI polling is paused.
- Android battery and network usage still need physical-phone measurement.
  Earlier desktop traffic reports do not establish Android drain.

## Current-code gaps covered by this slice

- DM history recovery can use an available authenticated installation holding
  the missing data, including a linked sibling or counterpart installation;
  see [ADR 0032](../ADR/0032-dm-offline-recovery.md). Groups/channels do not have
  equivalent durable missed-text catchup. Their successful publish forgets the
  outbound attempt; group resync retrieves MLS commits, not old message bodies.
  The owner explicitly includes closing this gap in the same slice.
- The existing Android lock screen is a cold-start DEK retry gate. No automatic
  UI re-lock after backgrounding exists; implement the accepted configurable
  lock policy independently of background key access.
- Original attachment downloads require an explicit request, but small image
  previews are currently scheduled automatically. Apply the accepted waiting
  policy without interrupting transfers initiated by the user.

### Recovery authorization findings

The expanded history scope requires a concrete protocol design, not only a
background polling change:

- Live group reception verifies the sender proof and MLS membership, then
  persists semantic text and its portable message origin. It does not retain
  the complete received proof and MLS epoch alongside every history row;
  see `private_group_runtime/data.rs`, `authentication.rs` and
  `conversation/history.rs` under `mosh-core/src/`.
- `MessageOrigin` authenticates the content and author, but not a complete
  historical authorization interval or original time. A valid content
  signature alone cannot establish that a departed member authored a message
  before removal. Group recovery must define historical eligibility, including
  joining, removal and rejoining, without disclosing pre-join history by accident.
- Existing group commit persistence and resync can supply epoch transitions;
  they are not by themselves a complete authenticated history-export protocol.
  Reuse bounded paging, durable cursors and atomic imports where appropriate,
  while retaining conversation-specific authorization.
- Recovery must preserve [ADR 0040](../ADR/0040-message-deletion.md): verified
  deletion journals and local tombstones take precedence over imported text;
  historical member status must not grant new deletion authority.
- [ADR 0038](../ADR/0038-authenticated-group-senders-and-dm-offers.md) already
  distinguishes verified live group traffic from legacy history. An update
  cannot retrospectively supply missing original authentication evidence.

These are findings about the baseline and requirements on the forthcoming
design. The holder-availability and membership-window policies are accepted;
the wire format, schema and their cryptographic enforcement remain to design.

## Implementation preparation

- Moss waiting lifecycle/interface, attachment selection and any intermediary's
  trust, metadata, abuse limits and operating budget.
- Background key-access implementation, safe migration and failure behavior;
  timer persistence, screen/lifecycle transitions and protection of interactive
  entry points under the accepted delayed-lock policy.
- Complete missed-history recovery across all three conversation kinds:
  source discovery, historical authorization, durable cursors, deduplication,
  deletion precedence and interruption/restart recovery.
- Implementation of the accepted lifecycle states, network changes, persistent
  user-stop handling, persistent Stop waiting preference, call expiry and
  delayed-event handling.
- Notification and call actions, one call owner, device selection, permissions
  and integration with existing audio routes and PiP.
- Quantified delivery latency, idle traffic, CPU/wakeups and battery budgets;
  acceptance on physical phones under comparable conditions.

The product interview ended on 2026-10-26. The owner also confirmed the testing
boundaries recorded in the specification: real independent installations over
the existing bridge/Moss, actual Android lifecycle and notification behavior,
and existing adapters for focused lock/permission checks. The specification is
published with `ready-for-agent`; this plan retains the research and decision
history. Concrete public contracts, dependencies, schemas and upstream Moss
changes still require the approvals prescribed by repository rules before
the affected implementation begins.
