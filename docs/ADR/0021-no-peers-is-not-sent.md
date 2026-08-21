# ADR 0021: no peers is a refusal, not a Sent

## Status

Accepted.

## Context

`check_publish_code` in `moss_ffi` mapped two Moss return codes to success:
`MOSS_OK` and `MOSS_ERR_NO_PEERS` (-6). Moss returns the second one when the
flood publish reached zero peers — the frame was built, sealed and then handed
to nobody. Every publish in the tree went through that one function, so a
message that provably left for no one came back as `Ok(())` and settled as
`Sent`.

`Sent` is the strongest word the DM has short of `Delivered`, and it is the
*only* word a group or a channel ever gets: neither has an acknowledgement, so
their messages settle at publish time and stay there. A group or channel
message sent before the mesh formed showed a plain sent tick forever.

Three things made this worse than it was when the tolerance was written:

- 0.7.4 put every conversation on one node, so one unmeshed node now means
  every open conversation, not one.
- The DM re-route after a relay is released (`drain_relay_results` →
  `route_prepared`) publishes directly and settles the result, so the same
  false `Sent` landed on the recovery path too.
- The auto-resend loop only re-drives attempts that already reached `Sent`. A
  refusal that was recorded as `Sent` burned a resend slot without a frame on
  the wire.

The probe had the tolerance written into it as a workaround: `channel-dial`
waited for a peer before sending, with a comment saying a publish with nobody
to publish to reports success.

## Decision

`MOSS_ERR_NO_PEERS` becomes its own error, `MossFfiError::NoPeers`, and the
caller decides what it means.

A user message fails, retryably. The same rule holds for all three kinds:

| kind | what a refusal does |
|---|---|
| DM (`route_send` Data, and the re-route in `drain_relay_results`) | `Failed`, attempt retained |
| private group (`publish_prepared`) | `Failed`, attempt retained |
| public channel (`publish_prepared`) | `Failed`, attempt retained |

Nothing new was built for this. `Outbox::settle(Err(..))` already keeps the
attempt record, `MessageDeliveryMeta::failed` already marks it retryable, and
each kind already has a `retry_message` that reopens the record and replays the
same bytes. On the render side `FailedMessageRetry` already draws a retry row
for an outbound `failed && retryable` message with a message id, in all three
kinds.

A control frame swallows the refusal, through an explicit
`MossNode::publish_room_best_effort`. These frames repeat on a cadence of their
own and carry no delivery status, so "no peers yet" says nothing about them:
the create-time KeyPackage (retried by `pump_handshake`), the peer announce,
voice frames, and the control and blob publishes of the group, the channel and
the org.

The tolerance is now a decision each call site makes and shows in its name,
instead of a line hidden in the code that classifies the return value.

## Consequences

- A message sent into a conversation whose node has no peers is red, with
  "no peers yet, so the message did not go out", and carries a Retry button.
  This is a visible change: that message used to look sent.
- `Sent` keeps its old meaning everywhere it still appears — handed to the
  transport, with at least one peer taking the frame. It does not mean anyone
  in the conversation received it; only the DM's `Delivered` means that.
- A re-send refused for want of peers no longer burns an auto-resend slot: the
  pump only counts a send that published or queued.
- In a unit test the node never meshes, so a real publish answers `NoPeers`.
  That is about the absent mesh rather than the code under test, so
  `tolerate_unmeshed_test_node` swallows it in `#[cfg(test)]` builds. A test
  that cares arms the outcome with `no_peers_next_test_publish`, which feeds
  the raw code through the real `check_publish_code`.
- `mosh-probe channel-dial --send-without-peers` skips the wait for a peer, so
  the refusal can be watched live instead of designed around.
- BUGS-TODO #18 (admin handoff frozen by a lost Commit) is not fixed here.
  Group control frames stay best-effort; that item needs confirmed delivery,
  which is a different mechanism.
