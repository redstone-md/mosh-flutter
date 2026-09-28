# DM device revocation, issue 27

Spec: https://github.com/redstone-md/mosh-flutter/issues/27.
Approved review baseline: `29e6317a77736520e43286bdb7e425710629af66`.
Commit on the current branch. No push, deployment or issue mutation.

## Scope

Remove one linked installation from the private signed device roster and one
existing text DM. Preserve the other installation and its counterpart, with
independent signing keys, Moss identities, MLS clients and encrypted stores.
Use the existing device settings, directed encrypted streams, durable MLS
transition transaction and semantic history importer. No dependency, table,
Moss source, wallet, subscription or hosted service change is proposed.

## Authorization and durable order

Extend the existing append-only roster chain with signed removal entries.
Keep existing addition serialization, signatures and digests valid. A removal
binds the parent digest, exact device and currently authorized signer under
a distinct version/context. Only an active device may change the roster;
refuse self-removal through this action. Verification calculates current
devices from the whole chain. A removed signer cannot authorize an extension.
Receivers accept extensions of their pinned roster, never a rollback, unrelated
root or competing branch. Concurrent roster fork merging stays out of scope.

Persist the signed removal and delivery intent before attempting transport.
Distribute verified roster extensions privately to linked installations,
including a removed installation's notification. Preserve that installation's
identity and history while marking its authorization revoked. Runtime owners
refresh the persisted identity before actions so a stale cached roster cannot
overwrite a newer one. An offline participant learns only after reconnecting.

For each affected DM, create a real MLS Remove commit targeting the exact
installation's leaf signer. Verify the resulting tree preserves every other
client. Save the commit evidence, updated topology, local MLS snapshot and
durable delivery journal together before installing or acknowledging it.
The signed evidence binds the conversation, group, next epoch, removed device,
authorized roster and original committer. Verify the actual MLS committer
matches that authorization. Retain evidence independently of acknowledgements.

Retry that same transition to every remaining admitted installation until
each durably acknowledges it. A removed installation's acknowledgement is
never needed for the protection boundary. New ciphertext uses the removal
epoch and the remaining topology. New history, recovery, old admission and
identity claims from a removed device fail current authorization checks,
including packets bearing an older valid roster or old request.

Extend the existing ordered recovery exchange to relay original signed removal
evidence. An honest offline installation verifies and applies missed Add and
Remove commits in order to its own MLS state before sending in the newer epoch
or importing new text. A revoked client gets no current Welcome, keys or text.
Already received history remains readable locally. No remote erasure is implied.

## Fresh authorization

An old QR, approval receipt, signed roster or MLS join request cannot undo a
removal. Keep consumed/expired request checks and require the current roster
for admission. A removed installation may create a fresh QR to request access
to the same user; it cannot use its retained conversations to switch users.
Reauthorization requires the existing human code approval against the roster
after removal and a fresh independent MLS join. Preserve old local history
while replacing only that installation's obsolete membership through the
ordinary authenticated Welcome path.

## Proposed contract and storage changes

The root AGENTS.md requires approval before public contracts or persisted
schemas change. The following changes are proposed for that approval:

- Add one typed device-link bridge operation, `revoke(device_id)`.
- Add typed snapshot fields for whether this installation is revoked and each
  requested removal's application status. Report pending while an affected
  remaining participant has not durably acknowledged its removal epoch;
  report applied only after all affected remaining participants have done so.
- Add an optional DM snapshot revocation state for the conversation banner and
  composer gate. Keep unrelated conversation and fingerprint contracts.
- Add backward-compatible optional encrypted identity/session fields for
  removal delivery, original evidence, acknowledgements and revoked membership.
  Add private signed roster/removal/recovery packet variants. Preserve old
  stored additions and admission evidence without rewriting them.

The Devices UI uses a remove action for another installation, a confirmation
dialog naming it, and persisted pending/applied status. Its copy explains that
offline participants must apply the new epoch and that received history stays
on the removed device. A revoked installation keeps its conversation history
visible with sending disabled and a fresh-link path. English and Russian copy
must match the runtime's actual states.

## Proposed test boundaries

The TDD skill requires confirmed boundaries before writing tests. Proposed:

- Public device-link and DM runtimes/snapshots in independent installation
  processes, with real Moss, OpenMLS and separate encrypted stores. Prove
  online revocation, durable pending status, restart, surviving messaging,
  honest offline recovery, history retention and fresh reauthorization.
- Signed roster, pairing/device packet and MLS crypto boundaries with real
  keys and persistence. Prove decryption refusal in the removed client's old
  MLS state, sync refusal, exact-device removal, unauthorized author/target,
  changed group/epoch, rollback, replay and stale QR/join refusal.
- Existing Flutter widget boundaries through `test/support/` for status,
  confirmation and the revoked conversation; the native Devices screen uses
  the real bridge and independent Moss process as required by ADR 0029.

Extra real installations may be used solely to prove that another device of
the same user remains authorized and that an honest offline participant applies
ordered changes. They do not expand the product scope beyond text DM.

## Execution and checks

- [x] Read issue 27, stored project guidance, architecture and ADRs 0029-0032.
- [x] Inspect roster, replay, admission, history and ordered recovery boundaries.
- [x] Confirm contracts, optional persisted fields, test boundaries and baseline.
- [ ] Prepare Moss, baseline Rust build and Flutter analysis.
- [ ] Red/green one removal slice through confirmed boundaries, then add the
  replay, restart, offline and fresh-authorization slices.
- [ ] Regenerate bridge bindings after API changes; check drift.
- [ ] Run Rust checks and focused test files during implementation.
- [ ] Update ADR, architecture and feature flow with Mermaid.
- [ ] Format, build, strict Clippy and Flutter analysis; full suites once at end.
- [ ] Measure at least 80% changed production line coverage and 70% branch
  coverage where available; report platform and toolchain limitations.
- [ ] Commit, run independent Standards and Spec code-review axes against the
  confirmed baseline, fix findings, verify affected checks and finish clean.

## Risks

The protection boundary is local acceptance of the removal epoch by honest
participants. An offline installation cannot acknowledge a change it has not
received. Pending status must survive a restart and never imply instant global
revocation. A holder of the required commits is needed for offline recovery.
Old received text remains accessible to the removed installation.

Crash ordering, stale cached identity writes, concurrent MLS transitions and
stale outbox ciphertext require focused checks. Serialize transitions under
the existing runtime owners; retain evidence after retry completion. Keep
new modules within repository limits and document necessary inherited size
exceptions. Older runtimes cannot implement the new removal protocol and must
fail closed when they cannot verify it. Linux is available here; Windows and
macOS require their runners. Android foreground remains issue 28.

The user approved this plan, contract/storage changes, test boundaries and
review baseline on 2026-09-28.
