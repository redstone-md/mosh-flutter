# Private group history

The Android background work uses the same native group owner and encrypted
installation store as desktop. Opening a screen is not a prerequisite for
receiving, saving, or recovering a group message. An available ordinary member
can supply its retained text and attachment offers while the original author
and administrator are offline. This work is part of IVO-142/143 under IVO-132.

Recovery covers a shared verified membership head, missing membership commits,
canonical admission instances, and retained removal/rejoin intervals. Native
software verification is separate from Android OS/device acceptance and public
network discovery latency; it is not acceptance of the whole Android specification.

## Original evidence and storage

Native live receive stages the installation's own OpenMLS ratchet. It verifies
the original dual MLS/Moss sender proof, actual decrypted MLS signer and original
MessageOrigin, then commits the semantic row, original acceptance evidence and
own next snapshot together. Refused writes install nothing; the same original
ciphertext can be retried. Historical imports use the shared conversation
coordinator and transaction rather than a second importer or foreign snapshot.

A successful local publication retains separate `local_publication` evidence;
it does not claim delivery or reading. Its Sent row, evidence and outbound
attempt retirement settle in one transaction. Refused settlement remains in the
ordinary pending writer and does not publish a second copy. Failed and pending
sends do not enter export manifests.

Attachment offers retain the complete original and preview manifests in the
ordinary encrypted history row. Public acceptance evidence serializes hashes,
original signatures and context facts, never a second plaintext copy of the
attachment keys. Recovery restores the offered descriptor without requesting
original or preview chunks. Deletion continues to own those history manifests.

New attachment envelopes additionally carry optional `sent_at_ms` inside the
existing dual SenderProof. All holders therefore retain the same author-claimed
time. Existing clients ignore it; absent legacy values remain receiver claims.
Neither a signature nor a holder receipt proves an independent creation time.

## Admission and compatibility

New KeyPackages carry an optional dual-signed key-package binding over the exact
TLS package and full MLS/Moss keys. The issuer stages its Add/replace, signs the
approved exact admission-association tuple, and saves its own next snapshot and
original association and exact targeted Welcome/Commit wire payloads before
publishing. A repeated original KeyPackage replays those accepted bytes, including
its original target, without another Add or epoch change. Pending joins retry the
same package with a 3–60 second backoff. A missing room path keeps a bounded
three-second retry cadence, and a newly usable discovery path wakes a pending
join. Successful Welcome replay is throttled to three seconds. These retries
reuse the accepted bytes without advancing the epoch. Unverified future associations have a separate
32-entry/1 MiB budget and are indexed by commit and claimed full signer. Welcome checks the
actual pinned author, group, next context, commit header, original byte hashes
and own joiner proof. An invalid supplied association refuses admission; absence
preserves legacy live compatibility without manufacturing the missing proof.

Admission references distinguish a native genesis, an exact verified Add/replace,
and `verified_since_checkpoint_v1` for older installations without an original
Add proof. Canonical references bind the exact group, original commit hash and
full admitted MLS key. Copying a display name or old reference does not establish
an entitlement. The current full MLS/Moss proof also authenticates retained old
intervals from the same installation's Moss identity. At most 32 checkpoints and
20 KiB of scope evidence are accepted. A later rejoin preserves known earlier
rights, excludes the verified absence interval, and does not reveal prejoin
messages. Missing evidence remains visibly incomplete.

A member missing commits can ask an available holder for the original encrypted
commits. Each record is bounded to 256 KiB, carried in 3,000-byte fragments, and
limited to 4,096 epochs ahead. The receiver stages every commit through its own
OpenMLS state, compares the actual branch, and commits its own next snapshot,
verified transition, and recovery head atomically. It never installs another
member's ratchet. Source and target changes cannot combine unrelated fragments.
Original organization signatures and verified roster authority survive relay;
current roster authorization is checked again in the storage transaction.
Removal and revocation use the same durable transition boundary.

Deletion excludes content from new manifests. For an already frozen manifest,
an erased slot retains only its authenticated origin and record hash, and needs
the original verified deletion before the receiver advances. If deletion replaces
a partially transferred large row, that slot restarts once with its new digest;
subsequent fragments continue normally. Deleted body or attachment keys do not
return through recovery.

## Transport and verification

Only discovery is room-scoped. Content, original proofs and holder vouches use
the existing encrypted recipient-directed Moss carrier. The shared transport
queue bounds queued work to 32 frames and 1 MiB and performs network sends
outside group/call owner locks. Every page rechecks the current group scope and
recipient. There is no group-key room fallback for historical content.

`private_group_history_flow` exercises independent real bridge installations:
ordinary-holder recovery with original author offline and holder restart,
original attachment offers without downloads, missing commit replay through an
ordinary member, prejoin exclusion, removal/rejoin interval selection, and
erasure during recovery. The explicit network acceptance
case for native receipt/import notifications without UI polling requires a real
signed reachable Waiting carrier and checks native readiness before sending;
loopback NAT absence is reported unavailable and never counted as delivery.
Native durability cases cover original proof retention, ratchet/snapshot refusal,
published-row evidence, atomic outbound retirement, tampered admission bindings,
changed interval/recipient/head proofs, organization authority, and notification
queue refusal/retry before UI polling. These are software
checks; real Android OS/device acceptance remains separate.

The existing runtime/session size exceptions remain. New files stay below 400
lines. The following recovery operations retain their entire bounded validation
or transaction sequence in one function (51–100 physical lines): `save_history`,
`persist_own_admission`, `verify_admission_association`, `import_history_journal`,
`continuous_membership`, `import_history`, `imported_history_row`,
`retained_history_record`, `GroupRecord::key`, `history_answer`,
`write_publication`, `persist_received`, `own_history_membership`,
`install_transition_evidence`, `history_content_page`, and
`publish_membership_change`.
The ordered real-process scenarios likewise retain setup, action and observable
assertions together. These exceptions do not increase wire or allocation bounds.
