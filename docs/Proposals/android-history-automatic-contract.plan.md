# Automatic private-group history contract

2026-10-26. The user accepted automatic recovery trusting a **current authorized
holder's historical-context assertion**, without administrator approval. That
policy and the exact wire/schema/snapshot scope below are approved for
implementation after clarification of the existing DM recovery mechanism.
Scope: [IVO-142](https://linear.app/ivoxygen/issue/IVO-142),
[IVO-143](https://linear.app/ivoxygen/issue/IVO-143), using
[the shared contract](android-history-contracts.plan.md). The native recovery path
and independent-installation checks are implemented in the current branch.
Review and physical Android background acceptance remain pending; this document
does not establish shipped behavior or handset reliability.

## Exact evidence and trust

Original MessageOrigin/HistoryContentProof stays with its original signature
and author. A holder signs a separate assertion, never a replacement origin.
Use existing Ed25519 Moss/MLS keys, fixed-order JSON tuples, domain prefixes,
complete keys and SHA-256 as specified in the shared contract.

`RecordBindingV1 = (conversation, mesh_id, occurrence_key, native_message_id,
kind, semantic_content_hash, complete_origin_hash, content_proof_hash_or_null,
original_author_mls_key, original_author_moss_key_or_null, claimed_sent_at_ms,
claimed_label)`. Hash with `mosh-history-record-binding-v1\0` prefix. Content
is exact Text UTF-8 bytes or complete original/preview AttachmentOffer. Preserve
the original signing inputs; no local delivery state, paths or holder labels.
After erasure retain binding hashes and tombstones, never recreate erased bytes.

`AcceptanceEvidenceV1 = (version=1, evidence_id, record_hash, original_origin_hash,
historical_context, author_admission_instance, holder_mls_key, holder_moss_key,
accepted_head, basis, first_evidence_hash_or_null, predecessor_hash_or_null)`.
`historical_context` and `accepted_head` contain epoch + GroupContext hash;
`basis` is `live_authenticated`, `local_publication` or `inherited_import`.
Sign that tuple with both holder keys under `mosh-history-acceptance-v1\0`.
Hashes reference immutable evidence; a remote “accepted” flag grants no rights.

`HolderVouchV1 = (version=1, conversation, mesh_id, org_pubkey_or_null,
record_hash, acceptance_evidence_hash, historical_context,
author_admission_instance, recipient_mls_key, recipient_moss_key,
recipient_current_admission, recipient_entitled_admission, holder_current_head,
holder_mls_key, holder_moss_key)`, signed by both holder keys under
`mosh-history-holder-vouch-v1\0`. The current head binds GroupContext plus current
verified org roster version/hash where applicable. No wildcard record/account
grant; export at most one current vouch and one selected acceptance object per
record. Keep original evidence hashes, not an unbounded recursive witness chain.

The receiver trusts the currently authorized vouch for historical association,
including inherited provenance. It verifies the available original evidence
but does not require every past witness online or still a member. A departed
witness signature alone cannot authorize a new import. A malicious current
holder can lie/collude with a removed author: this is the accepted trust cost.
Receipts, signed times and group member lists are not independent proof of
pre-removal creation. No automatic administrator signing, human review, quorum,
closing-root omission or all-holder membership barrier is introduced.

## Native acceptance and entitlement

Generate live evidence only after the existing dual-key/current-membership and
actual staged MLS-signer/plaintext checks succeed. Atomically store the row,
original proofs, full context/admission references, evidence and **own** advanced
MLS snapshot; only then publish/forward or expose durable acceptance. Preserve
equivalent native accepted-publication evidence for own sends without inventing
delivery. Failed/pending sends are not exported as accepted publications.

Imported rows retain their first available evidence and get `inherited_import`
provenance through the same protected native acceptance transaction; never mark
them live. A new vouch is generated automatically only for locally accepted
eligible rows. Request handlers cannot feed arbitrary old signatures directly
into this signing path. This controls honest software, not malicious signers.

Independently verify membership transitions on the receiver's pinned branch;
never import a holder's private MLS snapshot or accept a foreign self-signed
tree as the anchor. An admission instance hashes MLS group ID, canonical
Add/replace commit and admitted full key; genesis uses the pinned initial
context/creator key. Intervals are `[admission_epoch, removal_epoch)`.
Encrypted commits are verified through the receiver's own staged `MlsGroup`;
retain the resulting intervals with its own advanced snapshot. `PublicGroup`
cannot replay this application's encrypted commit log. A verified Welcome pins
its context/members, but an unsigned outer commit hash cannot establish the
canonical admission binding. Missing old bindings remain evidence_missing.
New admissions retain an optional joiner dual-key binding over group/mesh,
KeyPackage hash and full MLS/Moss keys, matched to the actual admitted leaf.

The asserted record context must fall within both author and entitled-recipient
verified intervals. The current recipient proves its actual current instance.
Ordinary offline leaves entitlement intact; new members get no pre-admission
history; removed recipients get no new export. Rejoin can recover earlier
eligible intervals only with retained authenticated full-key/Moss bindings to
the same recipient; it never includes the absence interval. Labels, account
claims and copied old admission IDs cannot grant that linkage.

On every page recheck current holder/recipient membership, exact recipient
binding and known revocations. Org groups additionally require verified current
roster membership and actual MLS credential/Moss-key binding; no admin role is
required. Cache timeless signature facts, not permission. Never lower a known
head/roster or accept a conflicting branch to satisfy a source. A stale isolated
holder cannot discover an unseen removal; instantaneous global freshness is
not promised. Already accepted local content survives a witness's departure.

## Automatic transport, persistence and completion

Reuse shared Probe/Offer/Pull/Page/Evidence messages and bounded source rounds;
no approval request/decision protocol. Group Pages carry original proof,
selected AcceptanceEvidence, HolderVouch and required public membership evidence.
Source changes restart at the selected frozen manifest's start; identical live
rows deduplicate, stale rounds cannot advance progress and refusals are retried.
Original author, former witnesses and administrators need not be online while
an authorized holder retains eligible content/evidence. No available holder
means waiting with bounded retry, never successful delivery by a wake hint.

Use existing recipient-directed encrypted Moss `send_to_peer` packets for group
content/proofs, including relay. Keep the single bounded callback demultiplexer
and fixed history prefix from the shared contract; callback sender is only a
claim, so verify application signatures. No group-key/room fallback: newcomers
know the current exporter key. Bound inbox/outbound work to 32 frames/1 MiB and
perform the up-to-five-second send outside group/call locks. No new dependency,
Moss API, stream ID or competing device-link/call inbox reader.

Keep exactly the three proposed encrypted tables: `conversation_recovery`,
`conversation_occurrences`, `group_history_evidence`. The latter uses typed
transition/evidence/vouch/local-acceptance prefixes. Only verified native
acceptance writes local-acceptance entries, never remote evidence decoding.
In one redb transaction verify unchanged authority context; save acceptance/vouch
evidence/provenance, deduplicated rows/manifests/index and next cursor; apply
existing personal/shared tombstones before visibility. Refused writes advance
nothing. No history attestation overrides deletion or grants deletion rights.

Add only the shared optional group/channel `history_sync` view and optional
StoredMessage `history_evidence`. Provenance distinguishes live, publication,
inherited and legacy without claiming timestamp verification. Existing bridge
operations remain; **zero administrator-review APIs or UI**. Regenerate bindings
for the snapshot changes. Complete covers the durably imported available
authorized manifest; unavailable evidence reports waiting/evidence_missing.

## Legacy and verification

Preserve all readable local legacy rows, including unsigned ones. They cannot
gain manufactured original signatures or original epoch receipts after upgrade.
A valid old MessageOrigin preserves content authorship, not signed time/context.
Automatic export is supported where retained authenticated admission/identity
evidence proves recipient entitlement and stored acceptance facts identify an
eligible context. The current holder may attest that association under the
accepted policy, retaining honest weaker legacy provenance. Do not guess a
missing membership interval from sent_at_ms or labels, synthesize a live receipt
for it, or blindly attest newly supplied signatures. A missing original author
proof/context remains evidence_missing remotely, never erased locally or silently
reported complete. Trust in unsupported legacy membership facts is not added.

Real independent installations verify alternate-holder recovery with author/
admin offline, live/import races, source switch/restart/refused writes, deletion,
admission/removal/rejoin and continued live traffic. Attacks cover wrong scope,
recipient/interval/origin, remote acceptance flags, departed-only witnesses,
backdated signatures offered without native acceptance and stale/forked heads.
Test that a newcomer with current exporter key/room subscription cannot decrypt
old pages over direct **or** relay. A malicious current-holder assertion is
documented as trusted policy, never advertised as cryptographic time proof.
