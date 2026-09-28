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
- [x] Prepare Moss, baseline Rust build and Flutter analysis.
- [x] Red/green one removal slice through confirmed boundaries, then add the
  replay, restart, offline and fresh-authorization slices.
- [x] Regenerate bridge bindings after API changes; check drift.
- [x] Run Rust checks and focused test files during implementation.
- [x] Update ADR, architecture and feature flow with Mermaid.
- [x] Format, build, strict Clippy and Flutter analysis; full suites once at end.
- [x] Measure at least 80% changed production line coverage and 70% branch
  coverage where available; report platform and toolchain limitations.
- [x] Commit, run independent Standards and Spec code-review axes against the
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

## Verification

Verified implementation at `0d8695f` on Linux against the approved baseline.
Independent Standards and Spec reviews have no open findings, including the
final duplicate-notification fix. Every implementation commit uses a
Conventional Commit subject. No push, deployment or issue mutation occurred.

- Rust formatting, build and `cargo clippy --manifest-path mosh-core/Cargo.toml
  --all-targets -- -D warnings` passed. Final test results across all targets:
  410 library tests, 9 device-link process tests, 2 identity tests, 1 historical
  time test and 17 multi-device DM process tests passed; 13 worker/legacy entry
  points were ignored. The doc-test target passed with no examples.
- The complete Rust command initially encountered a transient Moss listener
  bind failure (`start: -13`) during restart and a default-discovery timeout.
  Both scenarios passed in isolation without code changes; the subsequent
  complete multi-device process file passed all 17 tests. Live Moss discovery
  timing remains a test-environment risk.
- Flutter analysis and formatting passed. The full widget suite passed 877
  tests with 5 existing skips. The native Devices screen passed through the
  real bridge and an independent Moss installation on the final build.
- Bridge regeneration and a subsequent hash check showed no drift across all
  40 binding files. All four changed Mermaid diagrams rendered successfully
  and their sources still match the rendered diagrams.
- Changed handwritten production coverage: Rust **1,316/1,417 lines (92.87%)**;
  Dart **69/71 lines (97.18%)** and **21/23 branches (91.30%)**. Rust coverage
  includes independent-worker profiles; Dart combines full widget and native
  screen runs. Generated bindings and test-only code are excluded. Rust branch
  instrumentation requires a nightly toolchain, which is not installed here.

The real-process and signed-packet checks cover durable pending/applied status,
both offline removal directions, ordered Add/Remove recovery with the original
author unavailable, actual removed-client decryption refusal, denied old and
freshly signed sync requests, retained local history and fresh same-user MLS
admission. Higher correlated batch epochs survive restart without changing
history rows or cursors. Repeated known removal notifications preserve fresh
QR and pending approval state before Offer, after Offer and across restart;
new removals still invalidate obsolete approval state.

The implementation reuses existing MLS transactions, semantic history import,
recovery, directed transport and settings components. No dependency or table
was added. Windows and macOS checks remain for their runners. Offline protection
starts after honest participants accept the removal epoch; old received history
remains on the removed installation. Mixed-version availability is not promised.

## Changed files

- [dm-device-revocation.plan.md](dm-device-revocation.plan.md)
- [docs/ADR/0033-dm-device-revocation.md](docs/ADR/0033-dm-device-revocation.md)
- [docs/Architecture.md](docs/Architecture.md)
- [docs/Features/device-linking.md](docs/Features/device-linking.md)
- [docs/Features/private-dm.md](docs/Features/private-dm.md)
- [lib/l10n/app_en.arb](lib/l10n/app_en.arb)
- [lib/l10n/app_ru.arb](lib/l10n/app_ru.arb)
- [lib/src/features/conversation/conversation_banners.dart](lib/src/features/conversation/conversation_banners.dart)
- [lib/src/features/conversation/conversation_screen_body.dart](lib/src/features/conversation/conversation_screen_body.dart)
- [lib/src/features/conversation/conversation_snapshot.dart](lib/src/features/conversation/conversation_snapshot.dart)
- [lib/src/features/conversation/dm_revocation_banner.dart](lib/src/features/conversation/dm_revocation_banner.dart)
- [lib/src/features/device_link/device_link_provider.dart](lib/src/features/device_link/device_link_provider.dart)
- [lib/src/features/device_link/device_list.dart](lib/src/features/device_link/device_list.dart)
- [lib/src/features/device_link/device_revocation_dialog.dart](lib/src/features/device_link/device_revocation_dialog.dart)
- [lib/src/features/device_link/devices_settings_section.dart](lib/src/features/device_link/devices_settings_section.dart)
- [lib/src/rust/api/device_link.dart](lib/src/rust/api/device_link.dart)
- [lib/src/rust/device_link/types.dart](lib/src/rust/device_link/types.dart)
- [lib/src/rust/frb_generated.dart](lib/src/rust/frb_generated.dart)
- [lib/src/rust/frb_generated.io.dart](lib/src/rust/frb_generated.io.dart)
- [lib/src/rust/frb_generated.web.dart](lib/src/rust/frb_generated.web.dart)
- [lib/src/rust/private_dm_runtime/contracts.dart](lib/src/rust/private_dm_runtime/contracts.dart)
- [mosh-core/src/api/conversation_bridge.rs](mosh-core/src/api/conversation_bridge.rs)
- [mosh-core/src/api/device_link.rs](mosh-core/src/api/device_link.rs)
- [mosh-core/src/device_link/identity.rs](mosh-core/src/device_link/identity.rs)
- [mosh-core/src/device_link/identity_tests.rs](mosh-core/src/device_link/identity_tests.rs)
- [mosh-core/src/device_link/mod.rs](mosh-core/src/device_link/mod.rs)
- [mosh-core/src/device_link/protocol_tests.rs](mosh-core/src/device_link/protocol_tests.rs)
- [mosh-core/src/device_link/roster.rs](mosh-core/src/device_link/roster.rs)
- [mosh-core/src/device_link/runtime/actions.rs](mosh-core/src/device_link/runtime/actions.rs)
- [mosh-core/src/device_link/runtime/mod.rs](mosh-core/src/device_link/runtime/mod.rs)
- [mosh-core/src/device_link/runtime/receive.rs](mosh-core/src/device_link/runtime/receive.rs)
- [mosh-core/src/device_link/runtime/revocation.rs](mosh-core/src/device_link/runtime/revocation.rs)
- [mosh-core/src/device_link/runtime/revocation/tests.rs](mosh-core/src/device_link/runtime/revocation/tests.rs)
- [mosh-core/src/device_link/runtime/service.rs](mosh-core/src/device_link/runtime/service.rs)
- [mosh-core/src/device_link/types.rs](mosh-core/src/device_link/types.rs)
- [mosh-core/src/device_link/wire.rs](mosh-core/src/device_link/wire.rs)
- [mosh-core/src/frb_generated.rs](mosh-core/src/frb_generated.rs)
- [mosh-core/src/mls_crypto.rs](mosh-core/src/mls_crypto.rs)
- [mosh-core/src/mls_crypto/membership.rs](mosh-core/src/mls_crypto/membership.rs)
- [mosh-core/src/moss_ffi.rs](mosh-core/src/moss_ffi.rs)
- [mosh-core/src/persistence/dm_devices.rs](mosh-core/src/persistence/dm_devices.rs)
- [mosh-core/src/private_dm_runtime.rs](mosh-core/src/private_dm_runtime.rs)
- [mosh-core/src/private_dm_runtime/contracts.rs](mosh-core/src/private_dm_runtime/contracts.rs)
- [mosh-core/src/private_dm_runtime/devices/admission.rs](mosh-core/src/private_dm_runtime/devices/admission.rs)
- [mosh-core/src/private_dm_runtime/devices/authorization_tests.rs](mosh-core/src/private_dm_runtime/devices/authorization_tests.rs)
- [mosh-core/src/private_dm_runtime/devices/history/import.rs](mosh-core/src/private_dm_runtime/devices/history/import.rs)
- [mosh-core/src/private_dm_runtime/devices/history/mod.rs](mosh-core/src/private_dm_runtime/devices/history/mod.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests.rs](mosh-core/src/private_dm_runtime/devices/history/packet_tests.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests/recovery.rs](mosh-core/src/private_dm_runtime/devices/history/packet_tests/recovery.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation.rs](mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/bootstrap.rs](mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/bootstrap.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/forgery.rs](mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/forgery.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/multiple.rs](mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/multiple.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/recovery_barrier.rs](mosh-core/src/private_dm_runtime/devices/history/packet_tests/revocation/recovery_barrier.rs)
- [mosh-core/src/private_dm_runtime/devices/history/source.rs](mosh-core/src/private_dm_runtime/devices/history/source.rs)
- [mosh-core/src/private_dm_runtime/devices/history/types.rs](mosh-core/src/private_dm_runtime/devices/history/types.rs)
- [mosh-core/src/private_dm_runtime/devices/live.rs](mosh-core/src/private_dm_runtime/devices/live.rs)
- [mosh-core/src/private_dm_runtime/devices/mod.rs](mosh-core/src/private_dm_runtime/devices/mod.rs)
- [mosh-core/src/private_dm_runtime/devices/proof.rs](mosh-core/src/private_dm_runtime/devices/proof.rs)
- [mosh-core/src/private_dm_runtime/devices/recovery/epochs.rs](mosh-core/src/private_dm_runtime/devices/recovery/epochs.rs)
- [mosh-core/src/private_dm_runtime/devices/recovery/import.rs](mosh-core/src/private_dm_runtime/devices/recovery/import.rs)
- [mosh-core/src/private_dm_runtime/devices/recovery/mod.rs](mosh-core/src/private_dm_runtime/devices/recovery/mod.rs)
- [mosh-core/src/private_dm_runtime/devices/recovery/relay.rs](mosh-core/src/private_dm_runtime/devices/recovery/relay.rs)
- [mosh-core/src/private_dm_runtime/devices/recovery/source.rs](mosh-core/src/private_dm_runtime/devices/recovery/source.rs)
- [mosh-core/src/private_dm_runtime/devices/recovery/types.rs](mosh-core/src/private_dm_runtime/devices/recovery/types.rs)
- [mosh-core/src/private_dm_runtime/devices/rejoin.rs](mosh-core/src/private_dm_runtime/devices/rejoin.rs)
- [mosh-core/src/private_dm_runtime/devices/revocation/bootstrap.rs](mosh-core/src/private_dm_runtime/devices/revocation/bootstrap.rs)
- [mosh-core/src/private_dm_runtime/devices/revocation/delivery.rs](mosh-core/src/private_dm_runtime/devices/revocation/delivery.rs)
- [mosh-core/src/private_dm_runtime/devices/revocation/evidence.rs](mosh-core/src/private_dm_runtime/devices/revocation/evidence.rs)
- [mosh-core/src/private_dm_runtime/devices/revocation/mod.rs](mosh-core/src/private_dm_runtime/devices/revocation/mod.rs)
- [mosh-core/src/private_dm_runtime/devices/revocation/recovery.rs](mosh-core/src/private_dm_runtime/devices/revocation/recovery.rs)
- [mosh-core/src/private_dm_runtime/devices/revocation/transition.rs](mosh-core/src/private_dm_runtime/devices/revocation/transition.rs)
- [mosh-core/src/private_dm_runtime/devices/runtime.rs](mosh-core/src/private_dm_runtime/devices/runtime.rs)
- [mosh-core/src/private_dm_runtime/devices/types.rs](mosh-core/src/private_dm_runtime/devices/types.rs)
- [mosh-core/src/private_dm_runtime/snapshot.rs](mosh-core/src/private_dm_runtime/snapshot.rs)
- [mosh-core/tests/device_link_flow.rs](mosh-core/tests/device_link_flow.rs)
- [mosh-core/tests/dm_recovery/mod.rs](mosh-core/tests/dm_recovery/mod.rs)
- [mosh-core/tests/dm_revocation/mod.rs](mosh-core/tests/dm_revocation/mod.rs)
- [mosh-core/tests/dm_revocation/sync.rs](mosh-core/tests/dm_revocation/sync.rs)
- [mosh-core/tests/link_revocation/mod.rs](mosh-core/tests/link_revocation/mod.rs)
- [mosh-core/tests/link_support/api.rs](mosh-core/tests/link_support/api.rs)
- [mosh-core/tests/link_support/crypto.rs](mosh-core/tests/link_support/crypto.rs)
- [mosh-core/tests/link_support/dm.rs](mosh-core/tests/link_support/dm.rs)
- [mosh-core/tests/link_support/mod.rs](mosh-core/tests/link_support/mod.rs)
- [mosh-core/tests/link_support/protocol.rs](mosh-core/tests/link_support/protocol.rs)
- [mosh-core/tests/multi_device_dm_flow.rs](mosh-core/tests/multi_device_dm_flow.rs)
- [native_test/device_link_test.dart](native_test/device_link_test.dart)
- [test/features/conversation/dm_revoked_screen_test.dart](test/features/conversation/dm_revoked_screen_test.dart)
- [test/features/device_link/device_revocation_test.dart](test/features/device_link/device_revocation_test.dart)
- [test/support/message_builders.dart](test/support/message_builders.dart)
