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

Optional account proofs bind the MLS or Moss signing key to a device signing key
and a compact account certificate. The certificate contains a root public key
and signed key delegations; it never exposes device names or Moss addresses.
The original message, request and acknowledgement each countersign their proof.
Certificates are obtained after linking through the existing authenticated,
encrypted directed stream, including for previously linked installations.
Pairing messages retain their existing signed shape. Private keys stay in
encrypted storage; local roster checks prevent revoked devices from writing or
receiving account synchronization. Remote channel proofs establish account
attribution, without claiming an authoritative current remote-device roster.
An author's other device cannot acknowledge that author's deletion as a recipient.
Channels also compare locally verified own-device Moss keys, including removed
keys, before issuing a receipt. This local account map works while a linked
device waits for its compact certificate and never travels in public metadata.

The sender validates the entire selection before saving. Reception validates
the carrier, exact target, original author, request signature and current rights.
DMs and channels permit authors; groups also permit verified current admins.
Unknown org authority defers work. Verified loss of membership or moderation
rights rejects unaccepted local work and retains a personal tombstone. A separate
encrypted acceptance table stores the actual receipt admitted by conversation
policy and indexes its exact request digest; importing an own-device journal
cannot populate that table. Already
accepted requests survive subsequent role changes and departure of their receipt
signer. Remembering former admin keys alone never grants authority to new requests.

Previously unknown deletions are admitted under current membership and rights.
An obsolete recipient receipt can be replaced by a fresh durable receipt while
the requester remains authorized. For moderation, a verified receipt from a
current admin supplies endorsement independently of the participant forwarding
it; that admin need not be online. A current admin forwarding an authenticated
record also endorses it. Protected local acceptance survives both departures.

Unknown historical requests from a departed author or former admin without
current endorsement remain a pending product decision. External org role
snapshots contain no authenticated deletion cutoff: a new receiver cannot
distinguish an old accepted request from the same former member and an ordinary
participant signing a new request and receipt after departure or demotion. The
implementation rejects that forgery. Choosing whether to trust a participant's
historical attestation changes the approved recovery/authority contract and must
be settled before publishing the PR.

Legacy text with no stored correlation evidence is explicitly device-local.
An authenticated frozen own-device history exchange can establish exact text
correlation from its context, occurrence ID, timestamp, sender and original body.
An overlapping legacy history page preserves a locally verified live origin.
Legacy attachments with complete manifests, call IDs and signed group event IDs
can correlate personal deletions. A legacy row without a verified origin never
gains permission to delete for everyone after an update.
Personal tombstones retain a second exact correlation key for authenticated
legacy copies of new messages. This key is frozen before body or manifest erasure,
including when a shared placeholder is later erased personally. Shared deletion
never uses that legacy key to grant authority over an unverified message.
History writes compute this correlation even without metadata and use the same
author field as the native message, so late legacy replay is erased atomically.

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
Deletion receives inbound control without ticking queued publication, so a route
becoming reachable cannot publish a message before cancellation is saved.
Native command errors distinguish invalid input, permission, revocation and
persistence failures for the existing bridge error mapping.

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

New wire fields and encrypted tables are additive. Own-device history keeps the
old signed primary payload unchanged. Metadata travels in an optional outer
extension signed by the same device key over the primary packet signature and
complete metadata. Verification restores it before fragment assembly. Old
clients ignore the extension and still verify the primary history packet;
page sizes, retries and atomic cursors use the existing history protocol.
Previous clients continue ordinary messaging but neither apply deletion metadata
nor acknowledge it.
State recovery requires another reachable updated replica retaining the journal.
Loss of all encrypted copies cannot be repaired. No mechanism retracts screenshots
or externally saved files.

Generated bridge files retain their existing source-budget exception. Existing
runtime constructors, protocol dispatchers and broad platform integration
fixtures retain their established lengths: these exercise complete wire/state
transitions and separating them would obscure the admission sequence. The group
authenticated-control dispatcher is 51 lines with the additive deletion arm;
new deletion integration scenarios may reach 58 lines to keep their durable
send/legacy-admission/receipt/restart assertions together. New production logic stays within
feature-local modules and the normal budgets. Checks use encrypted redb, real MLS
and Moss, the existing independent-process harness, and Flutter `test/support`.
