# Private group history

The Android background work uses the same native group owner and encrypted
installation store as desktop. Opening a screen is not a prerequisite for
receiving, saving, or recovering a group message. An available ordinary member
can supply its retained text and attachment offers while the original author
and administrator are offline. This work is part of IVO-142/143 under IVO-132.

The current implementation checkpoint covers recovery at a shared verified
membership head. Membership-gap evidence exchange, canonical admission-instance
selection and removal/rejoin scenarios remain in progress; this checkpoint is
not acceptance of the whole Android specification.

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
same package with a 3–60 second backoff, so discovery warming or a lost Welcome
cannot strand an accepted join. Unverified future associations have a separate
32-entry/1 MiB budget and are indexed by commit and claimed full signer. Welcome checks the
actual pinned author, group, next context, commit header, original byte hashes
and own joiner proof. An invalid supplied association refuses admission; absence
preserves legacy live compatibility without manufacturing the missing proof.

Original native membership checkpoints are explicitly typed
`verified_since_checkpoint_v1`; they never impersonate an original Add. Native
transitions retain the verified own branch and full member keys. Missing or
conflicting branches remain waiting rather than rolling the local state back.

## Transport and verification

Only discovery is room-scoped. Content, original proofs and holder vouches use
the existing encrypted recipient-directed Moss carrier. The shared transport
queue bounds queued work to 32 frames and 1 MiB and performs network sends
outside group/call owner locks. Every page rechecks the current group scope and
recipient. There is no group-key room fallback for historical content.

`private_group_history_flow` exercises independent real bridge installations:
ordinary-holder recovery with original author offline and holder restart,
and original attachment offers without downloads. The explicit network acceptance
case for native receipt/import notifications without UI polling requires a real
signed reachable Waiting carrier and checks native readiness before sending;
loopback NAT absence is reported unavailable and never counted as delivery.
Native durability cases cover original proof retention, ratchet/snapshot refusal,
published-row evidence and atomic outbound retirement. These are software
checks; real Android OS/device acceptance remains separate.

The existing runtime/session size exceptions remain. New files stay below 400
lines. The following recovery operations retain their entire bounded validation
or transaction sequence in one function (51–84 physical lines): `save_history`,
`persist_own_admission`, `verify_admission_association`, `import_history_journal`,
`continuous_membership`, `import_history`, `imported_history_row`,
`retained_history_record`, `GroupRecord::key`, `history_answer`,
`write_publication`, `persist_received` and `own_history_membership`.
The ordered real-process scenarios likewise retain setup, action and observable
assertions together. These exceptions do not increase wire or allocation bounds.
