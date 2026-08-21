# ADR 0022: a send is one durable fact

## Status

Accepted.

## Context

A send leaves two rows on disk: the message, in its kind's history table, and
the outbound attempt, which holds the payload so a restart can replay bytes the
transport never took. `History::write_send` wrote them as two separate redb
transactions — append the message, then put or delete the attempt.

The rows are two halves of one statement, and splitting the statement made the
halves disagree. A crash between the two commits leaves a message on disk in
whatever state it was in when the first commit ran, with no attempt row behind
it. For a send that is what `Pending` means, because every kind files the
attempt as `Pending` before publishing:

1. `persist_send` — message and attempt both `Pending`.
2. the kind publishes (`route_prepared` in the DM, `publish_prepared` in the
   group and the channel).
3. `Outbox::settle` records the result in memory.
4. `persist_send` again — the outcome.

Replay already knew that a `Pending` attempt read from disk is abandoned:
whoever held it died with the process, so nothing will settle it. It comes back
as a retryable `Failed` — "app closed before the send completed" — which is
also what unblocks the DM's `retry_message`, whose "send already in flight"
gate reads that same status.

But that rule walks the attempt table. A message row that landed without its
attempt has nothing to walk, so it came back `Pending`: a spinner nothing would
ever settle, on a message with no record to retry from. The same shape appears
without a crash, when an attempt row is on disk but its JSON no longer parses
and replay skips it.

## Decision

**The two rows go down together.** `Persistence::commit_send` opens one write
transaction, writes the message row and writes or removes the attempt row in
it, and commits once. Both halves land or neither does.

The two writes *around* the publish stay two writes. The first one is not
redundant — it is what makes the payload survive a crash during the publish,
which is the entire reason an attempt record exists. What was wrong was not
that there are two of them, but that each was itself divisible.

**A `Pending` message with no attempt behind it is a failure, not a spinner.**
After both replay loops, `settle_orphaned_sends` fails any message still
reporting `Pending` that no attempt record backs:

| what came back | status | retryable |
|---|---|---|
| `Pending` attempt, payload intact | `Failed` | yes |
| `Pending` message, no attempt | `Failed` | no |

Not retryable, because without an attempt record there are no bytes to replay:
a retry button there would only ever answer "message missing". The rule heals a
database an older build already tore, and covers the unreadable attempt row,
which atomicity cannot.

Both rules live in the shared history store, so all three kinds get them from
one place and they are proved once rather than three times.

## Consequences

- A send interrupted by a crash is red rather than spinning, in all three
  kinds. This was already true for the common case before this ADR; what
  changes is the torn-write case, which used to spin forever.
- An interrupted send that still has its attempt record stays a **manual**
  retry. Re-sending it at rehydrate would mostly fire into a mesh with no peers
  yet, turning an honest "unknown" into a definite failure sooner rather than
  better; feeding it to the DM's auto-resend loop would require it to come back
  `Sent`, which is the lie ADR 0021 exists to forbid, and only the DM has such
  a loop.
- A resend after a crash whose original frame did leave is a duplicate. The
  peer already drops it: `MessageLog::holds_copy_of` matches on message id.
- `Persistence` now owns both key formats — `history_message_key` and
  `outbound_attempt_key` — because `commit_send` needs both and neither should
  be spelled twice.
- Nothing new was built. `Outbox`, `persist_send` and `retry_message` are
  unchanged; the change is one transaction where there were two, and one rule
  at replay.
