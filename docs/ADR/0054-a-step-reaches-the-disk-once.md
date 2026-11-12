# ADR 0054: a step's writes reach the disk together, and a frame leaves after them

Date: 2026-11-12
Status: Accepted and implemented for direct messages (MOSH-104).

## Context

Every write to the store was a transaction that waited for the disk before it
returned. A runtime makes them under its lock, so the lock is held for as long
as the disk takes. On a disk that answers in milliseconds nobody sees it. CI's
Windows runners took 15 to 44 ms on average for one synced write and up to
2.9 s, and there a DM send held the runtime for up to 15.6 s while the chat's
poll waited for the same lock (MOSH-103).

MOSH-103 counted the transactions per process and put the thirteen on the
receiver. A trace by call site shows they are the sender's. One text sent to a
connected contact was thirteen transactions on the sender:

| When | Transaction |
| --- | --- |
| The send command | the message and its attempt, as admitted |
| | the same pair, once the queue took it |
| | the MLS state and the session record |
| | the pair again, before the frame is sealed |
| | the MLS state and the record |
| | the MLS state and the record, with the ratchet that sealed the frame |
| | the pair, with what the transport answered |
| | the MLS state and the record |
| | the message row again, as the tail of the history |
| | the MLS state and the record |
| The tick that takes in the receipt | the pair, now delivered |
| | the MLS state and the record |
| | the session record, when it changed |

The receiver made three for the same text: the MLS state with the ratchet that
sealed its receipt, then the message row, then the MLS state again.

That order on the receiver was also wrong. The first of the three put the
ratchet that had opened the text on disk, and the receipt left, before the
text's own row was written. A crash in between lost the text: its key was
spent, and its sender, holding a receipt, never sent it again.

## Decision

**Inside a step a commit does not wait for the disk.** `Persistence::step`
starts one on the calling thread. Until it ends, that thread's transactions on
that store commit without a sync: they are readable at once, and they reach the
disk with the next sync. The step's end is one, `Persistence::sync` is one, and
so is any write from outside a step. The store is redb, and a crash leaves it
as its last sync wrote it. The transactions of a step therefore survive as a
prefix of the order they were made in or not at all, which is what each of them
promised its caller before: nothing later is on disk without what came before
it.

**A frame leaves after a sync.** `PrivateDmSession::saved` writes the ratchet,
syncs, and hands back what publishes the session's frames. What a frame tells
a peer is on disk before the peer hears it, and a restart cannot seal a second
frame with a key the first one used. A session with linked devices wrote its
ratchet before a frame already. One without them wrote it around the publish,
which a receipt sent after the tail save no longer has, so `saved` writes it
for both. The one session it writes nothing for is a joiner that still waits
for its Welcome: it has sealed nothing, and its key package leaves whether or
not the store took its placeholder.

**Frames sealed together leave after one save.** A tick seals every receipt it
owes, or every re-send that is due, then saves once and sends them. Before,
each of them saved the ratchet for itself.

**A receipt leaves after its text's row.** The session notes the receipts it
owes while it takes frames in. The runtime sends them from the tick once the
tail write has saved their rows, in the same step, so the row, the ratchet
that opened the text and the ratchet that sealed the receipt are on disk
before the receipt leaves, after one sync. A text whose row the store refused
is not acknowledged until a later tick saves it. An earlier frame of the same
tick, a Hello for one, can still put the opening ratchet down ahead of the
row. A crash there costs nothing: the sender holds no receipt and sends the
text again, sealed anew.

The DM runtime runs three things as steps: the send and retry commands, the
tick's outbox turn, and the tick's tail save with its receipts. Inside them a
frame leaves only through `saved`. The rest of a tick keeps a sync for every
write: device admission, history import, deletions and calls send packets by
other routes right after their writes, and those writes must be on disk first.

## Consequences

The transactions are the same thirteen and three. MOSH-104 asked for
noticeably fewer than fourteen per text, and what it meant to remove was the
wait under the lock. Merging them would have rewritten the refusal handling
each of them carries ([ADR 0037](0037-conversation-write-acceptance.md)) for
no fewer waits than this. The aim was one sync per frame that leaves and one
per step, and that is what a text costs now:

| One text | Syncs before | Syncs now |
| --- | --- | --- |
| Sender, the send command | 10 | 2: before the frame leaves, and at the command's end |
| Sender, the receipt's tick | 3 | 1 |
| Receiver | 3 | 1 |

In the real-process scenario that sends 40 texts
(`dm_recovery::recovery_switches_source_after_partial_import_and_restart_without_losing_live_text`)
the sender synced 559 times before and 154 times now, the receiver 171 and 70.
The remainder is the pairing, linking and history import around the texts.

The same scenario on a disk that takes 300 ms for a sync. The delay was a
sleep before every synced commit, patched in for the measurement on both
revisions and not kept:

| | Before | Now |
| --- | --- | --- |
| The scenario | 634 s | 135 s |
| A send command, average and longest | 13.9 s and 23.0 s | 2.4 s and 3.2 s |
| The longest tick | 22.0 s | 3.4 s |
| The longest chat poll | 5.6 s | 1.3 s |

A send still waits for the tick that holds the lock, then syncs three times
itself: once for the receipt of the text before it, which its own drain takes
in, and twice for its own text. The poll is not under a second, which
MOSH-104 asked for: a tick still syncs for work outside its steps, most often
for the ratchet before a frame that sealed nothing (below).

A crash now loses at most the step it interrupted, where before it lost the
transaction it interrupted. For a send that is the difference between a text
that comes back as failed with a retry, and a text that is not in the history
because the command that filed it never returned. Nothing a peer was told is
lost in either case.

This narrows what ADR 0037 calls acceptance inside a step: a write is accepted
when it commits, and durable at the step's next sync. A sync that fails at a
step's end is logged, and redb refuses every write after a failed commit, so
the writes that follow report it the usual way.

Left alone:

- Groups and channels write as before. Their publish path was not measured.
- A frame that seals nothing still saves the ratchet: a Hello, a typing hint,
  the identity claim a session repeats while one of its devices is offline.
  Each is one sync under the runtime lock (MOSH-106).
- The send command's two syncs are both under the lock. The second could move
  out from under it, the first cannot: the frame waits for it.
