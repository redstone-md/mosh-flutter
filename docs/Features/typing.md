# Typing indicators

Feature doc for typing indicators (spec #6): the counterpart (or group
members) sees "typing" while the composer is in use, and the hint dies
the moment a real message lands. Reference: [Private DM](private-dm.md),
[Architecture](../Architecture.md).

## The sequence

```mermaid
sequenceDiagram
    autonumber
    participant A as Alice (composer)
    participant RT as Alice's runtime
    participant W as control channel (MLS-encrypted)
    participant B as Bob's runtime
    participant UI as Bob's snapshot poll
    A->>RT: every keystroke, typing_signal
    Note over RT: refresh throttle: at most one frame per 3 s
    RT->>W: TypingIndicator (encrypted body)
    Note over W: body carries device + until_ms, never in the clear
    W->>B: decrypt = authenticate; forged hints drop here
    B->>B: stamp deadline from Bob's clock (+5 s)
    B->>UI: snapshot carries peer_typing_until_ms / typing_members
    Note over UI: hint lapses at the deadline, poll-driven expiry
    A->>W: send_message
    W->>B: DataEnvelope (the real message)
    B->>B: hint cleared at once, a delivered message contradicts typing
```

## The cadence and the expiry

- **Emit:** the composer calls `typing_signal` on every keystroke; the
  runtime re-emits at most every 3 s (`TYPING_REFRESH_MS`). Stopping
  input simply stops the calls — there is no sender-side "I stopped"
  frame.
- **Expiry:** the receiver owns the deadline. A hint stands for 5 s
  (`TYPING_EXPIRY_MS`) from delivery, stamped from the receiver's clock;
  the sender's `until_ms` inside the encrypted body is advisory and is
  never trusted.
- **Expiry is poll-driven:** no timer runs. The next tick/poll drops a
  hint past its deadline and files a `stopped` event. This is also where
  a cleared composer dies: a draft cleared without a message sent has no
  wire signal in this slice — the hint simply expires within the 5 s
  window (a documented deviation from "clear the moment the draft is
  emptied"; the receipt for that UX is that no new frame type was added
  for a state that self-heals in seconds).
- **A message beats a hint:** an inbound data frame from the typing peer
  clears their hint at once (DM: `clear_peer_typing`; group:
  `clear_member_typing`), whatever its deadline said.

## Where the state lives

| surface | DM | private group |
|---|---|---|
| snapshot field | `SessionSnapshot.peer_typing_until_ms` | `GroupSnapshot.typing_members: Vec<TypingMember>` |
| member identity | the counterpart (envelope + device body must agree) | `TypingMember { fingerprint, display_name, until_ms }` — fingerprint keyed, display name learned from their frames |
| event | pinned code 10 (`typing`), phases `started`/`stopped` into the event ring (capacity 64) via `push_app_event` | same ring, same code |

Group typing identifies WHICH member types; channels never carry typing
(no direct counterpart, and the channel wire is identity-free).

## Forge and mixed-version tolerance

- The body travels MLS-encrypted: only a member of the group can mint a
  ciphertext the receiver accepts, so a bystander cannot forge "someone
  is typing". A frame that does not decrypt drops silently (a field-log
  note under `verify`), never an error.
- Old clients ride the established unknown-envelope decode-drop: a build
  without the `TypingIndicator` variant fails `decode_json` and drops
  the frame — no typing shown, nothing breaks.

## Proof

State tests in `private_dm_runtime/state_tests.rs` (`MemoryNet`) and
group tests in `private_group_runtime.rs`:

- `typing_signal_travels_and_a_message_stops_it` — one keystroke, one
  encrypted frame, receiver-stamped window, a real message clears it.
- `typing_refresh_folds_keystrokes_to_one_frame_per_cadence` — five
  keystrokes, one frame; a refresh past the cadence re-emits.
- `typing_hint_expires_after_the_window_without_sleeping` — expiry by
  the fake clock, no sleeps.
- `forged_typing_indicator_does_not_set_the_hint` and
  `a_forged_group_hint_is_dropped` — garbage ciphertext and self-minted
  replay both stay down.
- `an_unknown_envelope_variant_is_dropped_by_the_drain` — the
  mixed-version decode-drop.
- `a_landed_hint_files_a_typing_event_into_the_ring` — event code 10.
- `group_typing_identifies_the_member_and_stops_on_their_message` — the
  group roster: fingerprint + display name, one entry per member.
