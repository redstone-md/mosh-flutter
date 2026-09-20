# Read receipts (DM)

Feature doc for the DM read-receipt flow: the two delivery ticks change
color when the counterpart opens the conversation — proof a human saw it,
never a third tick (see [[Read receipt]] in root `CONTEXT.md`). Reference:
[Private DM](private-dm.md), [Architecture](../Architecture.md).

## Flow

```mermaid
sequenceDiagram
    autonumber
    participant Bob as Bob (open DM screen)
    participant RT as DM runtime (Rust)
    participant Wire as mls-control channel
    participant Alice as Alice's runtime
    Note over Bob: toggle ON; messages on screen not yet read
    Bob->>RT: poll_session / mark_viewed(session_id)
    RT->>Wire: ReadReceipt { receipt_ciphertext_b64 } (one per message)
    Note over Wire: body {message_id} MLS-encrypted;<br/>only the MLS peer can mint one
    Wire->>Alice: ReadReceipt (decrypt = authenticate)
    Alice->>Alice: message.read = Some(true); event 9 "peer-read"
    Alice->>Alice: snapshot poll carries read:true
    Note over Alice: two ticks change color
```

## The rules

| rule | where it lives |
|---|---|
| One message id per frame (the ack shape) | `ControlEnvelope::ReadReceipt`, body `ReadReceiptBody { message_id }` |
| MLS-encrypted per message, forged = dropped | `handle_control` ReadReceipt arm — decrypt-or-drop |
| Default OFF, one app-level toggle, both values persist | `read_receipts::load/save` → `read-receipts.json` in the data dir |
| Symmetric: do not send, do not see | sender gate in `mark_viewed`; receiver gate in the ReadReceipt arm |
| DM only | no group/channel code touched; groups/channels have no receipt frame |
| Never a third tick | snapshot field `ChatMessage.read: Option<bool>` (own messages, `Some(true)` only when read) |
| Restart does not re-ask | `PersistedSession.read_message_ids` (serde default, pruned to the last 512) |
| Honest event log | `push_read_event` files pinned code 9 (`message_read`) on send and on receipt |
| Old clients degrade silently | unknown-envelope decode-drop, pinned by `a_receipt_from_a_newer_client_decode_drops` |

## The trigger

`mark_viewed(session_id)` is the api/Dart poll's "the screen is open" hook.
With the toggle on it receipts every counterpart message not yet receipted
(a per-session in-memory id set stops re-sends while the process lives). With
the toggle off it is a full no-op — no frame, no event.

## Mixed-version tolerance

An old client fails to decode the unknown `ReadReceipt` variant at
`decode_json` and drops the frame — it simply never colors. No handshake, no
capability negotiation.

## Proof

State-machine tests in `private_dm_runtime/state_tests.rs` on the in-memory
transport (`MemoryNet`):

- `a_message_settles_from_sent_to_delivered_to_read` — Sent→Delivered→Read,
  both event phases, duplicate receipt idempotence.
- `a_disabled_toggle_sends_nothing_and_ignores_inbound_receipts` — symmetry
  in both directions.
- `a_forged_receipt_never_colors_a_message` — garbage ciphertext + self-minted
  replay die; the honest receipt over the same link still colors.
- `a_receipt_travels_encrypted_per_message` — the id never rides the clear;
  only new messages receipt again.
- `read_state_survives_a_restart` — reopen on the same store, no re-ask.
- `a_receipt_from_a_newer_client_decode_drops` — unknown variant decode-drop.
- `read_receipts::tests::*` — the toggle file round-trips BOTH answers;
  broken/missing file reads as the default (off).
