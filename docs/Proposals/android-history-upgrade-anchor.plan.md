# Verified membership checkpoints for existing groups

Status: proposed; not approved or implemented. Supplements the approved
[automatic history contract](android-history-automatic-contract.plan.md)
for IVO-142/143. No administrator interaction is introduced.

## Existing-installation gap

The approved admission reference hashes the original Add/replace commit and
full admitted key. An upgraded installation's own verified current MLS tree
proves current membership, but may not retain that original binding. Deleted
old epoch secrets prevent reconstructing it from an encrypted commit log.
Missing bindings must not silently become an invented Add-derived identifier.

## Exact additional evidence type

Add a typed `VerifiedSinceCheckpointV1` reference alongside the existing
commit/genesis admission reference. It contains conversation/group ID, mesh ID,
verified GroupContext hash/epoch, full MLS key, full Moss key and the hash of
the retained authenticated binding between those keys. Its ID hashes that
fixed-order tuple under `mosh-history-membership-checkpoint-v1\0`.
Acceptance evidence and holder vouches name its typed reference; an untagged
commit-admission ID cannot be reinterpreted as this checkpoint.

Only the installation's protected native acceptance path may create a local
checkpoint, from its OWN persisted verified MlsGroup and authenticated full-key
bindings. No remote flag, imported snapshot, display name or claimed date can
create it. Missing full-key binding remains evidence_missing until verified.

Its entitlement starts at the exact verified context/epoch, never earlier.
Future verified transitions extend that local interval until removal. The
receiver independently intersects its own retained interval with each record's
context. A source's checkpoint cannot grant the receiver an earlier interval.
No rollback of known context, branch, removal or current org roster is allowed.
Org authority and the accepted current-holder historical-context trust remain
otherwise unchanged.

Removal closes the interval; rejoin starts a separate instance. Earlier eligible
intervals require the existing retained full MLS/Moss identity linkage; absence
stays excluded. Equal labels/accounts/keys alone do not bridge missing facts.

Only future protected acceptance/publication with a supported context can use
the checkpoint. Pre-upgrade rows remain readable locally; no original epoch or
receipt is manufactured for them. Unavailable older evidence is reported as
waiting/evidence_missing, not omitted to produce false completion.

Store these typed objects in the already approved group_history_evidence table;
reuse existing Evidence pages and optional provenance fields. No extra table,
bridge operation, dependency, administrator UI or user migration prompt.

Verify upgrade followed by offline recovery, storage refusal/restart, forged
remote checkpoints, attempted pre-checkpoint export, known removal and rejoin
absence through real OpenMLS/persistence and independent bridge peers.

AGENTS.md requires approval before changing public contracts or schemas. This
typed evidence extension needs that approval before runtime implementation.
