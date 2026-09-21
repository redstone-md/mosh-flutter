# PR2 design — unify conversation-kind runtime machinery

Branch: simplify/core-unify (stacked on simplify/comments).

## Shared typing module: `conversation/typing.rs`

Both DM and group re-implement the same four-part typing machinery:
refresh cadence gate, expiry window, event-ring pushes, deadline stamping.

The module owns:
- `TYPING_REFRESH_MS` (3s), `TYPING_EXPIRY_MS` (5s), `TYPING_EVENT_CODE` (10)
  — single source now (the DM/group copies were identical).
- `TypingGate` — the `last_send_ms` + `refresh allowed?` state, usable by
  both the DM's `publish_typing` and the group's.
- `push_typing_event(room_id, phase)` — the event-ring insert.
- `deadline(now) -> u64` — `now + TYPING_EXPIRY_MS`.

DM-specific (stays in DM): peer-typing single-slot state (`peer_typing_until_ms`).
Group-specific (stays in group): member roster map (`typing_members`).
Both call the shared gate/expiry/event helpers. The DM's
`note_peer_typing/expire/clear` and the group's
`note_member_typing/clear_member_typing` become thin wrappers over the
shared deadline + event helpers.

## Shared read-events: `conversation/read_events.rs`

DM-only today but the file lives in `conversation/` so a future kind gets
it for free: `push_read_event` moves from `private_dm_runtime.rs` (it only
uses `dlog` + `kinds`).

## Attachment quartet facade unification

The three runtimes' facade methods are structurally identical:
drain → lookup session → delegate → persist. The lookup+persist boilerplate
repeats 15 times (5 methods × 3 runtimes). Unify into a generic helper per
runtime using the `ConversationRuntime` map + a `SessionKind::missing()`
error constructor, e.g.:

```rust
fn with_session<T>(
    &mut self,
    id: &str,
    f: impl FnOnce(&mut GroupSession) -> Result<T, PrivateGroupError>,
) -> Result<T, PrivateGroupError>
```

Each facade method becomes one line. Error types differ per runtime, so the
helper is a small macro or a per-runtime 4-line helper — NOT a trait
abstraction across runtimes (their error types must stay distinct for the
bridge).

## Session plumbing unification

- `drain_inbound` in group+channel: same shape (inbox drain → route by
  channel prefix → per-session pump). The inbox claim closure is the only
  kind-specific bit; leave routing in place, extract the shared
  `Inbox::drain_for(prefixes, |message| ...)` helper into `inbox.rs`.
- `has_seen_message` dedup: DM + group both wrap `SeenFrames`; already
  shared via `conversation::dedup`. Verify no duplication remains.

## What PR2 explicitly does NOT do

- No trait unification of the three runtimes into one generic runtime —
  their wire envelopes, crypto, and authority models differ (MLS 1:1 vs
  MLS group vs plaintext). The `ConversationRuntime` shell already owns
  the common table machinery.
- No `api::` signature changes (bridge drift gate must stay green).
