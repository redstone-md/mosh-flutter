# ADR 0020: one inbox per owner, not one queue for everybody

## Status

Accepted. Closes the last shared stratum ADR 0019 left in place.

## Context

Every frame moss hands up arrives on one C callback, and that callback pushed
into a single process-global `Vec` — `RECEIVED_MESSAGES` in `moss_ffi`. Four
readers shared it: the DM, the private group, the public channel and the org.

None of them could take only their own, because the queue had no idea who
owned what. So each one ran the same routine, `drain_messages_where`:

1. take the whole queue out from under the mutex,
2. release the mutex,
3. walk the frames, keeping the ones whose channel it recognised,
4. lock again and put the rest back.

Three kinds, three copies of that routine, each behind its own runtime mutex.
The take and the put-back are two separate critical sections, so a second
reader can take, process and return frames of its own in between. Its
leftovers then go back to the front of a queue the first reader is about to
overwrite, and the first reader's leftovers come back behind frames that
arrived later. Same-kind frames are read out of order, and an MLS conversation
that reads a Commit before its predecessor drops it.

Until 0.7.4 the exposure was small: every conversation had its own node, so
these drains rarely overlapped in a way that mattered. 0.7.4 put every
conversation on one node (ADR 0019's sibling work), which makes the overlap
routine rather than rare.

The put-back also leaks. A frame nobody recognises is kept by every reader and
returned by every reader, forever.

## Decision

Split the queue by owner.

A kind registers what it recognises once per process and gets back an `Inbox`
handle. The moss callback files each frame under the first owner that claims
it. A drain takes that owner's queue and nothing else.

```rust
// private_dm_runtime.rs
fn dm_inbox() -> &'static inbox::Inbox {
    static INBOX: OnceLock<inbox::Inbox> = OnceLock::new();
    INBOX.get_or_init(|| inbox::register(is_private_dm_inbound))
}

// drain_inbound
let inbound = dm_inbox().drain();
```

There is no filtering left at the read side, no leftovers to put back, and no
state two kinds share. Order within an owner is a property of the structure
rather than of timing.

What a channel is called stays with the kind that names it: the claim is a
closure the kind supplies, so `inbox` holds no table of prefixes and ADR 0019's
rule — everything about the wire stays with the kind — still holds.

Frames nobody claims go to a bounded tail. `drain_all` (behind
`drain_received_messages`) returns every queue plus that tail; it is how tests
reset the world and how `wait_for_payload` reads a raw publish.

## Consequences

- A kind must register before the node that could deliver its frames starts. A
  frame that arrives before its owner exists lands in the unclaimed tail and no
  drain will see it, so every runtime claims its channels in its constructor,
  before any node of its own is up.
- Two runtimes of the same kind in one process (the two peers a test runs)
  share one queue, exactly as they shared the single global one.
- Overlapping claims are decided by registration order, first match wins. The
  four claims in the tree are disjoint by prefix (`mls-*` and `voice-call/`,
  `group-*`, `public-channel/` and `channel-blob/`, `org-control/`).
- The unclaimed tail is capped, so the old slow leak is gone.
- `drain_messages_where` is deleted.
