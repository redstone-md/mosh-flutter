# Retained public-channel history

After joining or restoring a public channel, Mosh automatically asks available
holders for retained messages. The original author can be offline. There is no
central archive: if no holder is available, the channel waits and live messaging
continues. Completion means the selected holder's available frozen view is saved,
not that every message ever sent has been found.

The channel snapshot exposes the same history notice states as private DMs:
`waiting_for_source`, `importing` and `complete`. A failed save or missing evidence
keeps recovery waiting. Another source or changed available history can start a
new round. Leaving removes the channel's cursor and derived occurrence index;
rejoining starts fresh.

## Proofs and existing history

History retains the exact original MessageOrigin and full attachment manifests.
A holder's signed page authenticates that holder, not the original author.
Original origins authenticate content, conversation and occurrence, while their
unsigned row labels and receive times remain claims. An identical retained copy
does not overwrite the first local time, label, delivery state or action ID.

Old unsigned channel rows can be restored with explicit legacy provenance. They
receive no original signature or shared deletion rights. Missing legacy IDs use
a separate deterministic namespace while old local action correlations remain
available for personal erasure. Conflicting content or authors under one native
action ID refuses the page.

Recovered attachments are offers. Neither original files nor auxiliary previews
are downloaded by history recovery, including after restarting. A holder keeping
an offer does not promise that it still has the file's chunks.

## Durability and resource limits

The shared engine lives in `conversation/recovery`; the channel adapter owns
room transport, original-author checks and conversion. It reuses the existing
DM cursor rules and existing encrypted history/deletion writer. DM packets and
authorization are unchanged. The channel uses its existing public room and blob
topic; this channel transport is not suitable for private-group history.

Source exports freeze ordered row locators and content bindings on disk. The
first Pull verifies the selected manifest inside that transaction; a changed
Offer is refused. The receiver atomically saves rows, occurrence conflicts,
source receipts and its next cursor in the existing redb store under its DEK.
Only then does memory advance. A refusal permits the same page to be retried.

Limits are 16 records per page, one partial serialized record up to 256 KiB,
3,000-byte fragment chunks, four active imports per installation, and 16 frozen
exports per channel. Exports expire after two minutes. Each inbox is bounded to
32 frames and 1 MiB; the complete signed carrier must fit the publication limit.
Idle probes back off from 5 to 60 seconds with jitter. Verified peer changes or
local history changes wake recovery; repeat Pulls are at least two seconds apart
and stalled sources time out after ten seconds. These are protocol limits,
not a measured Android battery budget.

The source's frozen deletion journal is validated before content appears.
Personal and shared tombstones also apply in the history admission transaction.
If a frozen record is subsequently erased, its slot retains the old binding and
advances only with an independently verified existing deletion. Saved partial
plaintext is discarded; erased content is never reassembled for that slot.

## Checks

`channel_history_flow` exercises independent installations through the public
bridge and real Moss: alternate holder with author offline, encrypted restart,
large pages, attachments, fragmented restart, a large deletion journal, and
deletion during fragmented recovery. Focused native inbox/storage tests cover
refused writes, source changes, original-proof tampering, legacy IDs, tombstones,
durable journal fragments, leave/rejoin, and bounded import/export slots.

The multi-step integration scenario functions may exceed the normal 50-line
function limit so each real-process setup, action and observable result stays
together. Production recovery functions retain the normal size limits.

Older clients keep live channel messaging and ignore the additional history
envelope. They cannot serve history retained only in the new protocol.
