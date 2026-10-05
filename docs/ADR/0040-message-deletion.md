# ADR 0040: durable message deletion

Status: accepted for issue #49. Product choices and contract changes are recorded
in [the approved plan](../Proposals/issue-49-message-deletion.plan.md).

## Behavior and ownership

DMs, groups and channels share one deletion command and one selection UI.
An explicit scope distinguishes personal erasure from deletion for everyone.
The message menu also starts bulk selection; a mixed selection cannot silently
delete only its eligible subset for everyone. Calls and group system events
allow personal erasure. Their underlying conversation state remains intact.

The interaction follows [Signal's message selection and scope choices](https://support.signal.org/hc/en-us/articles/360007320491-Delete-messages-alerts-or-chats).
Displaying the moderator in a deleted group message follows
[WhatsApp's administrator deletion convention](https://faq.whatsapp.com/1370476507114859/).
The approved Mosh behavior imposes no time limit on verified author deletion.

`message_deletion` owns target proofs, tombstones, merge rules, acknowledgements,
bounded paging and policy evaluation. Existing DM/group/channel owners supply
their current membership, roles, signing key and transport. The device-link
owner remains the sole consumer of the encrypted directed stream.

## Targets and authority

New text and attachment sends carry `MessageOrigin`: a full author signing key,
conversation, random occurrence ID, content hash and signature. Identical files
have different occurrence IDs. Attachment proofs cover the complete manifest,
including chunk encryption parameters. MLS reception compares the proof's author
with the actual staged MLS signer before committing ratchet advancement.
Channels verify the signature and compare the claimed fingerprint with its key.
Sender labels never grant deletion rights.

Optional account proofs bind the MLS or Moss signing key to an active device in
its certified roster. The original message, request and acknowledgement each
countersign their account proof. Private device keys stay in encrypted storage.
Compatible roster extensions let linked devices recognize the same author;
revoked devices cannot create new requests or receive account synchronization.
An author's other device cannot acknowledge that author's deletion as a recipient.

The sender validates the entire selection before saving. Reception validates
the carrier, exact target, original author, request signature and current rights.
DMs and channels permit authors; groups also permit verified current admins.
Unknown org authority defers work. Verified loss of membership or moderation
rights rejects unaccepted local work and retains a personal tombstone. Accepted
moderation can be forwarded by a current admin; members also retain the verified
admin keys they observed so accepted state survives subsequent demotion.

Legacy text with no stored correlation evidence is explicitly device-local.
Legacy attachments with complete manifests, call IDs and signed group event IDs
can correlate personal deletions. A legacy row without a verified origin never
gains permission to delete for everyone after an update.

## Atomic erasure and recovery

Encrypted `message_deletions` records retain target proofs after content erasure.
A transaction saves the journal, replaces matching history rows with empty rows,
cancels eligible outbound attempts and queues attachment cleanup. Empty rows
retain IDs and timestamps so frozen history cursors remain usable. Personal rows
are filtered from snapshots; shared rows render a localized placeholder.

A never-published outgoing message is cancelled. A personal deletion of an
already-published DM retains its original delivery buffer until the counterpart
acknowledges it. Replay, import and outbox writes consult the tombstone under the
same redb transaction and cannot restore content or a cancelled send. History
imports verify complete origin proofs after text fragments have assembled.

Confirmed shared state wins over pending or rejected state. Multiple valid
acknowledgements choose one deterministic signer so replicas converge. A receipt
binds the exact signed request digest and is published only after durable save.
The first eligible other participant confirms the request; this does not claim
that every member of a channel has received it.

DM/group metadata uses an MLS exporter key, AES-256-GCM with a fresh nonce,
conversation AAD, epoch binding and author signature. It does not consume normal
application generations. Channels carry signed public metadata. Existing native
services exchange digests and request missing journal pages every two seconds.
Empty journals remain silent until another participant advertises deletions.
Pages contain at most 16 records and normally at most 24 KB. Authenticated 3 KB
fragments fit the existing Moss transport wrappers; reassembly verifies the full
digest, bounds memory and separates carriers.

Active linked devices exchange personal and shared journal records through the
existing directed stream. Account, recipient and roster checks precede decoding.
Each page echoes a random request ID; late pages from an earlier restart or
roster cannot finish a new pull. The journal also retains records for unopened
conversations and later-linked devices. Native conversation policy controls
whether shared records may subsequently be forwarded to participants.

## Attachments and compatibility

Deletion removes transfer slots and in-flight chunk buffers. A removed voice
widget disposes its existing player, and native range requests become unknown.
Cache cleanup uses app-owned paths, live transfer leases and encrypted references
from all conversations and retained outbound attempts. Filenames are compared
after sanitization. A durable GC queue retries busy files and advances past
still-referenced entries. User-saved external copies remain intact.

New wire fields and encrypted tables are additive. Previous clients continue
ordinary messaging but neither apply deletion metadata nor acknowledge it.
State recovery requires another reachable updated replica retaining the journal.
Loss of all encrypted copies cannot be repaired. No mechanism retracts screenshots
or externally saved files.

Generated bridge files retain their existing source-budget exception. Existing
runtime constructors and broad platform test fixtures keep their prior lengths;
new logic belongs in feature-local modules. Checks use encrypted redb, real MLS
and Moss, the existing independent-process harness, and Flutter `test/support`.
