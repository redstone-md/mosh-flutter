## Problem Statement

Android users miss Mosh calls and messages when they leave the app or lock the
phone. Keeping the ordinary mesh fully active is not an acceptable substitute
for a background design: availability must not require excessive idle network,
CPU or battery use. Existing desktop idle measurements do not establish the
phone's battery or traffic baseline.

The current startup biometric key gate also prevents a reclaimed background
process from reading encrypted history while the phone is locked. Users need
private notifications, configurable access to chats and uninterrupted calls
without having to authenticate after every brief app switch.

Live notifications alone are insufficient. Private DMs, private groups and public
channels must recover messages missed while offline as part of this same scope,
without introducing a central message archive or exposing unauthorized history.

## Solution

Provide background calls and message notifications inside the normal Mosh APK,
without FCM or a Google Play services dependency. An economical, explicit opt-in
Mosh waiting mode in Moss reuses its relay carrier instead of retaining the full
ordinary mesh workload. A persistent quiet notification lets the user stop
waiting; the app accurately reports when Android restrictions limit availability.

Separate the Mosh app lock from background key access. After the first Android
unlock following reboot, background reception can use the encrypted local store
without another biometric prompt. Chat access follows a configurable delay that
applies equally to backgrounding and locking the phone. Notification previews
remain an explicit privacy choice.

Recover missing history from reachable authorized holders, including someone
other than the original author. Wait automatically when none is reachable.
Preserve membership boundaries, original message identity and deletion state.
No protocol can recover data absent from every remaining copy.

## User Stories

1. As an Android user, I want an incoming voice call to alert me while Mosh is minimized, so that I do not have to keep a chat open to receive calls.
2. As an Android user, I want an incoming video call to alert me while the phone is locked, so that locking the screen does not make me unreachable.
3. As a callee, I want to answer from the incoming-call presentation, so that I can join without first navigating through my chats.
4. As a callee, I want to decline a pending call from its notification, so that I can refuse it without opening the conversation.
5. As a callee, I want cancelled and expired calls to stop ringing and clear their actions, so that stale notifications do not invite me into a finished call.
6. As a user returning to connectivity, I want expired call offers to remain expired, so that delayed delivery does not produce a new ring for an old call.
7. As a caller, I want call history and outcomes to reflect the actual direction and result, so that background handling does not mislabel outgoing, missed or declined calls.
8. As a participant, I want an accepted voice or video call to continue after minimizing Mosh, so that I can use another app during the call.
9. As a video-call participant, I want the existing floating view and Android Picture-in-Picture to keep working, so that background support preserves the current call experience.
10. As an account owner with linked devices, I want answering on one device to select one participating call device, so that other devices do not create competing media sessions.
11. As an account owner, I want stale notification actions to be checked against the current call, so that an old answer or decline cannot affect a replacement or accepted call.
12. As a privacy-conscious callee, I want microphone and camera capture to remain off before acceptance, so that an incoming alert cannot start recording me.
13. As a user of Mosh app lock, I want to answer and control a call without unlocking my chats, so that taking a call does not expose my conversations.
14. As a private-DM participant, I want notifications for new messages while Mosh is waiting in the background, so that I notice activity without keeping its interface open.
15. As a private-group member, I want notifications for new group messages in the background, so that group reception is not limited to an open group screen.
16. As a public-channel reader, I want notifications for new channel messages in the background, so that channel reception is not limited to an open channel screen.
17. As an Android user, I want receiving a message or wake signal to remain distinct from reading it, so that background work does not falsely send read receipts.
18. As a user without Google Play services, I want the same background feature in the normal APK, so that receiving activity does not require a Google-enabled build.
19. As a privacy-conscious user, I want FCM excluded from this delivery design, so that Google-hosted push is not required to carry Mosh events.
20. As a user, I want ordinary STUN address discovery to remain available, so that excluding FCM does not unnecessarily remove working NAT traversal.
21. As an Android user, I want a quiet persistent waiting notification, so that I can see whether Mosh is maintaining background availability.
22. As a new user, I want waiting enabled after setup, so that I do not need to discover a separate service or APK to receive background activity.
23. As a user, I want Stop waiting to remain off across app and phone restarts until I explicitly re-enable it, so that Mosh respects my saved choice.
24. As a call participant, I want Stop waiting to leave my current call running, so that stopping future waiting does not hang up my conversation.
25. As a user transferring a file, I want Stop waiting to leave my already-started transfer running, so that stopping future waiting does not discard active work.
26. As a user, I want a clear way to re-enable waiting, so that a deliberate stop does not permanently prevent background reception.
27. As an Android user, I want swiping Mosh from recent apps to preserve waiting, so that dismissing the task is not silently treated as Stop waiting.
28. As an Android user, I want ordinary system process reclamation to recover waiting through supported Android lifecycle mechanisms, so that memory pressure does not permanently disable reception.
29. As an Android user, I want background operation to resume after the first system unlock following reboot, so that restarting the phone does not require opening every chat.
30. As an Android user, I want explicit OS Stop and Force stop to be respected until I reopen Mosh, so that the app does not fight my decision to stop it.
31. As a user who previously chose Stop waiting, I want reopening after an OS stop to preserve that separate off preference, so that reopening the app does not silently re-enable waiting.
32. As a user, I want one understandable battery-optimization exemption request, so that I can decide whether to allow the background behavior without repeated prompts.
33. As a user declining the exemption, I want Mosh to report limited availability honestly, so that I can understand why immediate background delivery may not work.
34. As an Android user, I want denied notification, microphone or camera permissions to produce recoverable behavior, so that refusal does not crash the app or falsely claim full operation.
35. As a mobile user, I want waiting to recover after Wi-Fi/mobile changes and temporary loss of connectivity, so that I do not need to restart Mosh manually after changing networks.
36. As a private-DM participant, I want to recover messages missed while offline, so that reconnecting restores the conversation rather than only new live messages.
37. As a continuously admitted private-group member, I want to recover messages from my offline interval, so that being offline does not lose group history.
38. As a public-channel reader, I want to recover available retained messages missed while offline, so that channels have the same complete recovery scope as other conversations.
39. As a returning participant, I want an authorized holder other than the original author to serve missing history, so that recovery can proceed while the author is offline.
40. As a returning participant with no reachable holder, I want recovery to wait and retry automatically, so that I do not have to recreate or manually repair the conversation.
41. As a privacy-conscious participant, I want history to remain on participants' devices rather than a new central archive, so that background reception does not change the storage model.
42. As a new private-group member, I want recovery to respect the boundary at my admission, so that adding offline recovery does not expose pre-join conversations.
43. As a private-group member, I want removed members to receive no new history exports, so that removal continues to restrict access.
44. As a rejoining private-group member, I want the interval when I was not a member to remain inaccessible, so that rejoining does not bypass the group's membership boundaries.
45. As a participant recovering history, I want authentic message identity and authorship preserved, so that another holder cannot silently replace content or impersonate its author.
46. As a participant, I want recovery and live reception to deduplicate the same message, so that reconnecting does not add duplicate conversation rows.
47. As a participant, I want interrupted recovery to resume safely after restart or source replacement, so that a disconnect does not corrupt progress or strand the conversation.
48. As a participant, I want verified deletions and my local erasures to survive recovery, so that downloading history cannot resurrect removed content.
49. As a user with older history, I want existing readable messages preserved without invented verification guarantees, so that an update does not delete my history or falsely authenticate legacy rows.
50. As a user of Mosh app lock, I want background reception to continue after the first Android unlock even when Mosh itself is locked, so that the app lock protects chats without making me unreachable.
51. As a user, I want encrypted storage and Keystore protection retained under the new background policy, so that background key access does not turn my history into plaintext storage.
52. As an existing user, I want key-policy migration to preserve my exact database key and history, so that upgrading cannot replace or orphan my encrypted conversations.
53. As a user encountering a failed or interrupted migration, I want a recoverable authentication path, so that a storage error cannot silently reset my identity or data.
54. As a user, I want automatic Mosh app lock choices of immediately, 1, 5, 10 or 30 minutes, with a 1 minute default, so that I can balance access protection and convenience.
55. As a user, I want Android screen locking to follow the same selected delay as backgrounding, so that locking my phone does not independently force immediate Mosh authentication.
56. As a user returning before the delay expires, I want to reopen my chats without another fingerprint prompt, so that brief app switches remain convenient.
57. As a user returning after the delay expires, I want authentication before any chat content appears, so that delayed callbacks or device sleep cannot expose expired access.
58. As a user, I want temporary system permission dialogs and file pickers not to count as leaving Mosh, so that normal interactions do not cause spurious re-locks.
59. As a user, I want notifications, background sync and call answers not to extend my chat-unlock deadline, so that background activity cannot silently keep my chats unlocked.
60. As a privacy-conscious user, I want names and message text hidden by default while Mosh app lock is active, so that notifications do not expose protected conversation details.
61. As a user, I want independent choices for showing names and message text, so that I can choose the disclosure level I find useful.
62. As a user who enables text previews, I want full message text on the Android lock screen where system settings permit it, so that I can read a notification without opening Mosh.
63. As a user, I want preview disclosure to leave chat access locked and read status unchanged, so that a visible notification is not treated as unlocking or reading the conversation.
64. As a user with stricter Android notification settings, I want Mosh to respect those settings, so that an app preference cannot override my system privacy choice.
65. As a mobile user, I want waiting to receive text and attachment offers without automatically downloading new media or clear previews, so that background activity does not spend data on unrequested downloads.
66. As a user who starts a transfer, I want it to continue when I minimize Mosh, so that background waiting policy does not interrupt deliberate work.
67. As an Android user, I want lower idle network, CPU and battery consumption measured alongside delivery reliability, so that a quiet network graph does not come at the expense of missed calls or messages.
68. As a desktop user, I want background-related changes to preserve bidirectional messaging, recovery and calls, so that Android improvements do not reintroduce one-way conversation failures.
69. As a developer of another Moss application, I want existing default behavior preserved unless I opt into the new waiting mode, so that Mosh's requirements do not regress gaming or peer-to-peer SSH.
70. As a user, I want availability and recovery status to reflect actual runtime state, so that an unavailable holder, OS restriction or wake hint is not presented as successful delivery.

## Implementation Decisions

- **One delivery scope.** Background calls, notifications, complete missed-message
  recovery for all three conversation kinds and measured idle efficiency belong
  to the same completed feature. Internal implementation can proceed in verified
  layers; live notifications alone are not completion.
- **One installation owner.** Reuse the installation's shared native Moss node,
  encrypted persistence, conversation owners and native media engine. Android
  execution ownership must not depend on a mounted chat, Activity or Flutter
  polling widget, and must not create a second node, store or competing call
  owner. All three conversation kinds need independent background servicing.
- **Explicit waiting mode.** Opt into an economical Moss lifecycle using the
  existing relay carrier. Transition between waiting and active user work
  without losing authenticated state or stranding connections. Ordinary
  desktop, gaming and SSH defaults remain unchanged. The current Moss C API
  lacks this lifecycle; stop/start on the same handle is not a working substitute.
- **Transport and wake trust.** No FCM or Google Play services dependency. Google
  STUN remains allowed for address discovery. An untrusted intermediary may
  forward short encrypted wake signals, with self-hosting possible. A wake
  signal is not delivery, a read receipt or call acceptance. Validate real
  activity through existing authenticated conversation protocols. Bound replay,
  duplicate hints, expiry, retries and unsolicited work; do not build a central
  message archive. No provider, hosting location or deployment is selected.
- **Android execution.** Keep waiting in the same APK with a quiet persistent
  notification. Specify a supported Android execution, permission and restart
  strategy before implementation. A foreground service alone does not bypass
  Doze, and a service category for an ongoing call must not be assumed to permit
  arbitrary idle discovery. Target Home/minimized, screen lock, recent-task
  removal and ordinary process reclamation. After reboot, support begins after
  the first system unlock; no before-unlock delivery guarantee is made.
- **User intent.** Initially enable waiting after setup. Persist Stop waiting
  until explicit re-enabling across process and device restarts. Leave current
  calls and user-started transfers running, then retain the off preference.
  Treat OS Active apps Stop and Force stop as explicit stopping requiring manual
  reopening, not as reclamation to evade with a restart loop. Reopening must not
  overwrite a separately persisted Stop waiting choice.
- **Battery consent and permission refusal.** Offer the battery-optimization
  exemption once, and report limited availability on refusal without nagging.
  Distinguish waiting state from actual ability to post notifications or receive
  immediately under current OS restrictions. Handle denied/revoked permissions
  and network changes without retry storms or unsupported capture attempts.
- **Call ownership and presentation.** Reuse authenticated signaling, expiry,
  caller cancellation, call refusal and participating-call-device selection.
  Notification actions identify and revalidate the exact session and call;
  stale actions cannot affect a replacement or accepted call. Preserve ringing,
  call history, audio routing, floating video and system Picture-in-Picture.
  Answering or controlling a call does not unlock chats. Do not start microphone
  or camera capture before acceptance or bypass Android permission requirements.
- **Key access and migration.** After the first Android unlock, allow background
  access to the database DEK without a new biometric prompt, including a cold
  reclaimed process and a subsequently locked screen. Keep at-rest encryption
  and Keystore protection. This deliberately changes the old per-use biometric
  key-release boundary; authentication instead protects interactive chat access.
  Migrate the same DEK through an authenticated foreground flow, durably verify
  the new wrapping before retiring the old one, and retain a recoverable old
  path on interruption or failure. Never regenerate the DEK, replace history or
  enter recursive key recovery merely because background key access fails.
- **Mosh app lock.** Offer immediate, 1, 5, 10 and 30 minute delays, defaulting to
  1 minute. Use one grace deadline from leaving interactive use; Android screen
  lock obeys it and neither shortens nor restarts an existing deadline. Return
  before expiry requires no fresh authentication. Check expiry before exposing
  chats after return or deep sleep; do not depend on a timer callback running on
  time. Preserve a valid deadline through ordinary process reclamation; an
  unverifiable deadline must not bypass authentication. Temporary system dialogs
  do not trigger false exits. Notifications, sync and call answers do not extend
  access. Reuse Telegram's timing pattern, not its different presets/default.
- **Notification privacy.** Mosh app lock and Android screen lock are separate.
  Hide names/text by default while Mosh app lock is active; independently allow
  names and message text, including full lock-screen text where the user opted
  in and Android settings permit it. Generic notifications must omit protected
  details from fields and metadata, rather than relying only on private
  visibility. Previews do not unlock chats or create read receipts. System and
  notification-channel restrictions take precedence.
- **Recovery sources and access.** Use reachable authorized retained copies;
  the original sender need not be online. Retry or switch sources when needed,
  and report waiting when no holder is available. Private-group access starts
  at admission, excludes new exports to removed members and excludes periods
  of nonmembership after rejoining. Ordinary offline periods retain access.
  Public-channel recovery can include all available retained history. Preserve
  the distinct authority rules of ordinary private groups and organization
  groups; transport reachability alone grants no history access.
- **Recovery evidence and durability.** Reuse existing DM recovery's bounded
  pages, source rounds, durable cursors, deduplication and atomic message/progress
  imports where applicable. Keep conversation-specific authorization separate.
  Current group MLS resync carries commits, not missed text. Stored semantic
  rows and portable content signatures alone do not establish historical
  membership, creation time or a removal cutoff. Define sufficient authenticated
  historical evidence before adding group history exports; a departed signer
  must not gain access or fabricate accepted history by backdating a message.
  Do not replace a receiver's MLS state with another device's private snapshot.
  Preserve original message identity, reject conflicting imports and keep live
  delivery working during recovery. Completion covers the verified available
  authorized history, not an invented global archive or channel total order.
- **Deletion and legacy data.** Apply existing verified deletion-journal and
  personal-erasure rules atomically with imports. Tombstones must prevent
  resurrection; past membership must not grant new deletion authority. Keep
  older readable history and do not retroactively label missing original
  authentication evidence as verified. Existing accepted tombstones survive
  later role and membership changes.
- **Attachments.** In waiting mode, receive text, signaling and attachment offers
  without starting automatic media or clear-preview downloads. Continue
  user-started transfers in the background and through Stop waiting. Recovery
  of a descriptor is not a claim that every history holder can serve its original
  file; retain actual transfer availability and readiness semantics.
- **Repository boundaries.** This spec approves behavior, not exact new public
  API signatures, schemas or dependencies. Prepare concrete contract/migration
  proposals for approval as required by repository rules. Moss work requires
  upstream maintainer coordination; do not edit its submodule or sibling
  consumers merely because this architecture was selected.

## Testing Decisions

- **Confirmed test seam.** The owner confirmed the following boundaries on
  2026-10-26: the primary automated scenario uses independent real Mosh
  installations through the existing public bridge and real Moss. Extend that
  scenario for calls and history instead of introducing a separate mock protocol.
  Android notification actions and lifecycle transitions are additionally
  observed at the actual application/OS boundary. Use existing adapters only for
  focused lock, time, permission and presentation tests.
- **External behavior.** Assert messages, durable history, actual notification
  contents/actions, call outcomes, selected media owner and whether protected
  chat content is visible. Do not test private method calls, polling counts or
  implementation-shaped snapshots as substitutes for user-visible outcomes.
- **Prior art.** Reuse the real-Moss multi-device DM/recovery harness, independent
  peer processes, bridge-driven native call scenarios, Android linked-DM
  integration flow, and existing lock-screen, call-presentation and PiP adapters.
  Extend these owners rather than creating parallel storage or network fixtures.
- **Calls.** Cover Android with Windows/macOS, foreground/background/locked
  reception, answer/decline, cancellation/expiry, delayed/replayed offers,
  simultaneous linked-device actions, stale notification actions and one media
  owner. Verify no pre-accept capture, correct history/ringing, ongoing call
  continuation and existing routing/floating-video/PiP behavior.
- **History.** Cover all three conversation kinds, unavailable original sender,
  alternate holder, all holders temporarily offline, source failure/switching,
  duplicate live/imported messages, interruption/restart and persistence refusal.
  Assert bounded progress, correct completion/waiting and bidirectional live
  messaging throughout recovery, including the prior one-way-DM regression.
- **Authorization.** Exercise pre-join exclusion, ordinary offline membership,
  removal and rejoining, organization authority, forged/altered history,
  backdated departed-member content, obsolete epochs, unauthorized sources and
  legacy unverifiable rows. Verify deletion precedence, local-only erasure,
  retained accepted tombstones and no unauthorized deletion authority.
- **Key migration.** Verify the same preexisting encrypted history and identity
  remain readable after migration, including interruption, refused writes,
  cancelled authentication and unavailable keys. Exercise warm and cold
  background reception after first unlock. Missing keys must not create new
  encrypted stores or silently reset existing data.
- **Lock and disclosure.** Exercise every timeout with controllable time, screen
  off before/after backgrounding, timely/late return, deep sleep, process
  reclamation, file pickers and permission dialogs. Assert no chat-content flash
  after expiry and no deadline extension from notifications or calls. Inspect
  notification fields/metadata with previews off and each disclosure setting;
  verify system settings can restrict further and previews do not mark read.
- **Lifecycle and refusal.** On Android, cover Home, screen lock, task removal,
  ordinary reclamation, reboot before/after first unlock, app Stop waiting,
  explicit OS Stop/Force stop, network changes and permission/exemption refusal.
  Verify saved off intent, no automatic resurrection after user stopping and no
  duplicate runtime ownership. Distinguish these cases in the result report.
- **Physical acceptance.** A release Android ARM64 build on a real phone must
  demonstrate supported Doze/background-call and notification behavior. CI,
  emulators and mocked lifecycle callbacks do not establish OEM reliability,
  radio activity or battery consumption. Capture actual build/device/OS,
  permission/exemption state and supported limitations.
- **Efficiency.** Establish comparable physical-phone and desktop idle baselines
  before optimizing: fixed durations, build, network, conversation/peer counts,
  UI/screen state and startup versus steady state. Measure per-process traffic,
  CPU, wakeups/wakelocks and phone battery use; compare empty, available and
  offline conversations with waiting enabled/disabled. Establish numeric
  acceptance budgets from those baselines and record before/after results
  alongside call/message latency. No battery percentage or traffic target was
  agreed during the interview; do not fabricate one or claim desktop traces
  prove Android drain.
- **Checks and isolation.** Run relevant Flutter analysis/tests, Rust
  formatting/tests/Clippy and real-dependency integration checks. Regenerate
  and verify bindings if bridge contracts change. Build Android for ARM64 with
  existing release signing/package verification. Keep default Moss consumers
  unchanged and verify opt-in behavior through an agreed upstream test scope.
- **Completion.** Require demonstrated delivery, all-kind recovery, safe key
  migration, privacy and measured idle efficiency together. Record untested
  physical conditions explicitly; a successful build or mocked notification is
  not end-to-end acceptance.

## Out of Scope

- FCM, a Google Play services requirement, a separate distributor APK, and a
  blanket ban on Google STUN.
- A central message archive, recovery of data deleted from every remaining
  holder, guaranteed original-file availability from every history source, or
  an always-online delivery guarantee when no authorized copy is reachable.
- Immediate delivery before the first Android unlock after reboot, bypassing
  user Force stop/OS Stop, or promising universal OEM reliability despite
  restrictions or refused permissions.
- New group calls, changes to which conversations support calls, changes to
  public-channel encryption, or a new single-publisher channel model.
- Automatically downloading new media/clear previews while waiting, unlocking
  chats by answering a call, or using notification visibility as a read receipt.
- Retrospective authentication of legacy data that lacks the original evidence.
- Altering default Moss behavior for other applications, unapproved upstream
  edits, selecting/deploying new hosted infrastructure, or changing billing.
- iOS background delivery and unrelated desktop UI redesigns.

## Further Notes

- This is the refined Android/background and recovery specification associated
  with [issue 94](https://github.com/redstone-md/mosh-flutter/issues/94). It does
  not replace or close that issue's broader cross-platform measurement work.
- Product decisions were settled in the 2026-10-25/26 design interview. The
  testing boundaries above were explicitly confirmed on 2026-10-26. Publishing
  this spec does not claim implementation or release acceptance.
- Respect the accepted decisions on Android waiting and background key access,
  together with the existing ADRs on shared node ownership, native media,
  participating call device selection, DM recovery and message deletion.
- The inspected baseline is Mosh v0.24.3. Fifteen targeted native Moss tests and
  a separate lifecycle probe established live relay forwarding and the absence
  of a reusable stop/start waiting lifecycle. They did not establish an
  economical Android receiver, cold-key migration or physical Doze acceptance.
- The official Telegram Android source at commit
  [3de37c8cfb039452be7398909461da6288babf15](https://github.com/DrKLO/Telegram/commit/3de37c8cfb039452be7398909461da6288babf15)
  was the requested auto-lock timing reference. Mosh retains its own agreed
  intervals and default.
- Exact Android execution/category choices, authentication/storage APIs,
  portable-history evidence, wire/schema changes and numeric energy/latency
  budgets must be made concrete during implementation preparation. They were
  not silently selected by the product interview; existing repository approval
  boundaries still apply.
