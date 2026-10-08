# Issue 46: call concurrency research

Research date: 2026-10-08. Product decisions remain open in the
[video-call plan](issue-46-video-calls.plan.md). This note addresses Q8 of the
design interview for [issue 46](https://github.com/redstone-md/mosh-flutter/issues/46).
It does not approve a new coordination protocol.

## Telegram's documented behavior

- The server sends the first incoming request to all active devices of the
  receiving user. The first device to invoke `phone.acceptCall` wins; the server
  discards that same call on the other devices and subsequently communicates
  with the winning device. This selects a device for one call.
  [Official call flow](https://core.telegram.org/api/calls#one-to-one-calls).
- `phone.receivedCall` separately marks the receiving user as busy until that
  call ends. The server then rejects other incoming calls with
  `phoneCallDiscardReasonBusy`. This reservation can start while the original
  call is still ringing, before acceptance.
  [Official method documentation](https://core.telegram.org/method/phone.receivedCall),
  [official call flow](https://core.telegram.org/api/calls#one-to-one-calls).
- The reservation RPC is optional. The documented API permits clients such as
  webradios to omit it and establish parallel calls. Therefore user-wide busy
  behavior is a client policy supported by the server, rather than an absolute
  limit of Telegram's media protocol.
  [Official call flow](https://core.telegram.org/api/calls#one-to-one-calls).
- Acceptance can fail with `CALL_ALREADY_ACCEPTED`, `CALL_ALREADY_DECLINED` or
  `CALL_OCCUPY_FAILED`; the last means the user is already making another call.
  [Official accept documentation](https://core.telegram.org/method/phone.acceptCall).

## What the official desktop client actually does

Source inspection uses Telegram Desktop commit
`68d1365911fb2c680dd8c7519782b4dbc7f02b7e`, retrieved on the research date.

- `Call::startIncoming` always sends `phone.receivedCall`. Its successful
  completion changes `Starting` to `WaitingIncoming`. User acceptance happens
  separately in `actuallyAnswer`. The documented optional reservation is
  therefore part of the normal desktop incoming-call path.
  [Incoming setup](https://github.com/telegramdesktop/tdesktop/blob/68d1365911fb2c680dd8c7519782b4dbc7f02b7e/Telegram/SourceFiles/calls/calls_call.cpp#L396),
  [answer](https://github.com/telegramdesktop/tdesktop/blob/68d1365911fb2c680dd8c7519782b4dbc7f02b7e/Telegram/SourceFiles/calls/calls_call.cpp#L464).
- If a new incoming request reaches a desktop already in a call or group call,
  `Instance::handleCallUpdate` sends a Busy discard. `inCall` includes pending
  outgoing and incoming states, apart from its explicit Busy, confirmation and
  rating exclusions. It does not wait for established media.
  [Incoming refusal](https://github.com/telegramdesktop/tdesktop/blob/68d1365911fb2c680dd8c7519782b4dbc7f02b7e/Telegram/SourceFiles/calls/calls_instance.cpp#L680),
  [local occupancy](https://github.com/telegramdesktop/tdesktop/blob/68d1365911fb2c680dd8c7519782b4dbc7f02b7e/Telegram/SourceFiles/calls/calls_instance.cpp#L842).
- Desktop also uses the Busy discard reason for an explicit rejection of a
  pending incoming call. A Busy result alone cannot prove that another active
  call exists. Mosh should keep explicit refusal and automatic busy distinct.
  [Hang-up reason selection](https://github.com/telegramdesktop/tdesktop/blob/68d1365911fb2c680dd8c7519782b4dbc7f02b7e/Telegram/SourceFiles/calls/calls_call.cpp#L697).

## Current Mosh boundaries

A user has separate device keys, Moss nodes and MLS clients. The verified device
roster authenticates those installations. Each DM has its own admitted clients;
text fans out to those clients, and returning installations recover from an
available admitted participant. These mechanisms authenticate and eventually
deliver state, but the documented architecture supplies no atomic call-occupancy
authority spanning every DM of one user.
[Architecture](../Architecture.md),
[ADR 0029](../ADR/0029-private-desktop-device-linking.md),
[ADR 0030](../ADR/0030-linked-desktop-dm-clients.md),
[ADR 0032](../ADR/0032-dm-offline-recovery.md).

The current native call slot belongs to `PrivateDmSession`. Start and acceptance
check that session; another offer while that slot exists is ignored. The Flutter
host retains one selected session for call presentation and one audio
orchestrator. Neither establishes exclusive occupancy across linked
installations. The accepted call model already requires agreement on one
participating device per user for a particular call.
[Native call controls](../../mosh-core/src/private_dm_runtime/calls.rs),
[voice-call ownership](../Features/voice-calls.md),
[ADR 0043](../ADR/0043-one-device-per-user-in-a-call.md).

## Inference about disconnected devices

Assume two linked devices cannot exchange occupancy updates. Each can reach a
different contact. Each device's observations are compatible with both cases:
the sibling is idle, or the sibling has accepted another call. If both must be
allowed to accept without coordination, both can become active. Authentication,
retries and conflict resolution after reconnection cannot prevent the earlier
overlap. This is an application of the safety/availability tradeoff under
partition, not evidence that Mosh already implements a particular consistency
policy. [Gilbert and Lynch, sections 2 and 4](https://groups.csail.mit.edu/tds/papers/Gilbert/Brewer2.pdf).

Strict user-wide exclusivity therefore needs a defined admission authority and
must sometimes delay or refuse a call when a device cannot obtain the required
authorization. A policy that lets every isolated linked device call independently
can offer only best-effort user-wide busy behavior. Selecting one device for the
same call and selecting one call across different contacts are separate
requirements. Extending Moss can carry their protocol, but cannot make missing
information available during a partition. These are design inferences from the
[existing per-device architecture](../ADR/0030-linked-desktop-dm-clients.md) and
the [partition argument](https://groups.csail.mit.edu/tds/papers/Gilbert/Brewer2.pdf).

## Recommended product decisions to confirm

1. Treat a call as occupying the user, so a free sibling normally cannot accept
   an unrelated second call. Keep call waiting and hold outside issue 46.
2. Reserve occupancy for a sent outgoing call or admitted incoming ring, then
   retain it through acceptance, media setup and reconnection. An incoming ring
   duplicated across devices is still one call. Release on a confirmed terminal
   transition or the defined expiry.
3. Keep Busy, explicit refusal, no answer and unavailable as different outcomes.
   Busy requires authenticated occupancy evidence; lack of connectivity alone
   does not establish another call.
4. Decide the partition contract before choosing a coordination mechanism:
   strict exclusivity with possible refusal while authorization is unavailable,
   or best-effort occupancy that allows isolated devices to call and requires
   an explicit later conflict rule. Do not claim both guarantees.

## Remaining unknowns

- Telegram's cited API documents receiver reservation precisely. They do not
  specify when an outgoing caller becomes reserved across its other devices,
  or the complete server ordering for simultaneous cross-calls. The desktop
  local Busy guard is insufficient evidence for those server guarantees.
  [Call flow](https://core.telegram.org/api/calls#one-to-one-calls),
  [desktop guard](https://github.com/telegramdesktop/tdesktop/blob/68d1365911fb2c680dd8c7519782b4dbc7f02b7e/Telegram/SourceFiles/calls/calls_instance.cpp#L680).
- Mosh must decide what happens when both users call each other simultaneously,
  when two siblings start outgoing calls to different contacts, and when a
  refusal races with another device's answer. The existing accepted ADR does
  not settle those cases. [ADR 0043](../ADR/0043-one-device-per-user-in-a-call.md).
- The occupancy expiry after a device crash, stale-state recovery and which
  other devices may end a reservation need separate protocol design. This
  research introduces no schema, transport or consensus implementation.

Checks consisted of primary-source inspection and local architecture review.
No Telegram calls or Mosh runtime tests were performed.
