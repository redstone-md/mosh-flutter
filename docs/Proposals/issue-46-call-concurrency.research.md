# Issue 46: call concurrency research

Research date: 2026-10-08. The design interview accepted user-wide busy behavior
from outgoing start or admitted incoming ring through setup, active media and
reconnection. The strength of that guarantee during network separation and its
coordination mechanism remain open in the [video-call plan](issue-46-video-calls.plan.md).
This note addresses Q8 for [issue 46](https://github.com/redstone-md/mosh-flutter/issues/46).
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

- Each installation owns independent signing keys, Moss identity and MLS state.
  A current roster member can authorize a roster extension; the original key is
  not an always-online call authority. Concurrent roster forks are refused rather
  than merged. [ADR 0029](../ADR/0029-private-desktop-device-linking.md),
  [ADR 0033](../ADR/0033-dm-device-revocation.md),
  [roster verification](../../mosh-core/src/device_link/roster.rs).
- `DmTopology` records the two users and admitted clients of one DM.
  `route_device_frame` sends to reachable admitted clients and succeeds after
  at least one send. It is not a majority vote or proof that all siblings are
  idle. [Topology](../../mosh-core/src/private_dm_runtime/devices/types.rs),
  [fan-out](../../mosh-core/src/private_dm_runtime/devices/live.rs).
- The current native call slot belongs to one `PrivateDmSession`; the Flutter
  host selects one session and owns one audio orchestrator. Neither supplies
  atomic user-wide admission across installations and DMs.
  [Call controls](../../mosh-core/src/private_dm_runtime/calls.rs),
  [voice-call ownership](../Features/voice-calls.md).
- Independent text use is already promised: a linked desktop can communicate
  while the original is off. The native integration scenario stops the original
  and then exchanges text between its sibling and the contact. This proves text
  behavior, not a matching guarantee for calls.
  [Feature contract](../Features/private-dm.md#linked-desktops),
  [real-process scenario](../../mosh-core/tests/multi_device_dm_flow.rs).

## One device for a call versus one call for a user

For one incoming call, all candidate receiving devices share a single originating
device. That caller can choose one authenticated acceptance and confirm that
selection before receiving devices start media. This is a proposed use of an
existing participant as the authority for that call, not an implemented protocol.
Setup can fail if the originating device disappears. It does not require every
sibling to be online. The accepted call model already requires one agreed device
per user. [ADR 0043](../ADR/0043-one-device-per-user-in-a-call.md).

Two unrelated calls have different originating devices and potentially different
DM memberships. Their callers do not share an account-wide admission authority.
Selecting one answer independently for each call can still leave one user active
in both. Existing per-DM fan-out cannot establish global exclusivity by itself.
This is an inference from [DM topology](../../mosh-core/src/private_dm_runtime/devices/types.rs).

## The partition decision

The following are hypothetical product scenarios, not runtime test results.
Assume the user has exactly two authorized devices, MacBook and Mac mini.

| Scenario | What MacBook can establish |
| --- | --- |
| Mac mini is powered off; MacBook can reach its contact. | No answer from Mac mini does not prove it is idle or off. |
| Mac mini is calling Alice; MacBook can reach Bob but neither device nor their contacts can relay occupancy between the two paths. | MacBook sees the same absence of sibling information and may start a second call. |
| The paths reconnect after both devices started different calls. | A conflict rule can end one call now; it cannot undo the earlier overlap. |

The inability to distinguish these cases creates a safety/availability tradeoff.
Strict exclusivity needs authorization that only one side can obtain; every
isolated device cannot independently proceed. This is a design inference, not
a claim that a specific consensus mechanism is mandatory.
[Gilbert and Lynch, sections 2 and 4](https://groups.csail.mit.edu/tds/papers/Gilbert/Brewer2.pdf).

| Viable contract | Product cost and design obligations |
| --- | --- |
| Keep calls available from an otherwise ready device when its siblings are unreachable. Reject second calls on authenticated known occupancy. | User-wide busy is best effort during network separation. Different calls may overlap until occupancy exchange becomes possible. On reconnection, detect the conflict and apply a documented rule with a visible explanation. The losing call may end unexpectedly. |
| Guarantee at most one call per user, even while siblings cannot communicate. | Require a defined call authority or intersecting quorum before admission. If the required authorization cannot be reached, refuse or wait and show unavailable, rather than invent Busy. With a fixed authority, its absence blocks other devices. A majority of a stable two-device membership requires both; one powered-off device therefore blocks calls. |

Quorum membership cannot be recomputed from devices that appear online locally:
each isolated device could then call itself a quorum. A strict design must also
define membership changes, durable admission and crash recovery. Clock-based
expiry needs explicit timing assumptions; timestamps alone do not prove that a
remote device stopped. These are requirements to investigate if the strict
contract is selected, not a proposed consensus implementation.

## Recommendation and exact interview question

Recommend availability with best-effort user-wide busy. This fits the established
ability to use a linked desktop while the original is off and avoids making calls
depend on one particular home computer. The recommendation assumes users should
have the same device independence for calls as for text; that preference still
needs confirmation. [Existing text contract](../Features/private-dm.md#linked-desktops).

Ask: "Mac mini дома выключен или недоступен, MacBook в поездке видит контакт.
Разрешаем звонок с MacBook, принимая возможность двух разговоров на разных
устройствах при разделении сети? Или гарантируем один разговор на пользователя,
но блокируем звонок, если нельзя получить разрешение общего координатора или
необходимых устройств? Рекомендую первый вариант."

The already accepted user-wide policy remains the normal behavior in both
contracts. Its partition guarantee is the choice. Keep text messaging independent
of this call-admission decision.

## Remaining unknowns

- Telegram's cited API documents receiver reservation precisely. They do not
  specify when an outgoing caller becomes reserved across its other devices,
  or the complete server ordering for simultaneous cross-calls. The desktop
  local Busy guard is insufficient evidence for those server guarantees.
  [Call flow](https://core.telegram.org/api/calls#one-to-one-calls),
  [desktop guard](https://github.com/telegramdesktop/tdesktop/blob/68d1365911fb2c680dd8c7519782b4dbc7f02b7e/Telegram/SourceFiles/calls/calls_instance.cpp#L680).
- For simultaneous calls between the same two users, recommend agreeing on one
  pending call before enabling media, instead of letting both Busy responses
  cancel the conversation. This is a separate per-pair decision; it does not
  solve cross-DM occupancy on disconnected siblings. Exact ordering and handling
  of refusal-versus-answer races still need protocol design.
- The occupancy expiry after a device crash, stale-state recovery and which
  other devices may end a reservation need separate protocol design. This
  research introduces no schema, transport or consensus implementation.

Checks consisted of primary-source inspection and local architecture review.
No Telegram calls or Mosh runtime tests were performed.
