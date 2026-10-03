# DM offline recovery, issue 26

Spec: https://github.com/redstone-md/mosh-flutter/issues/26.
Review fixed point: `c21b7e1bf25af0b6dfa959c3a21a3b5515ea7a7d`.
Commit on the current branch. No push or deployment.

## Scope and design

Recover text and missed MLS admission epochs in one existing DM. Each linked
installation retains its own signing keys, MLS client and local storage key.
Use the existing directed encrypted Moss stream and signed device packets.
Discovery stays automatic. No new table, bridge operation, gateway method,
wallet or hosted service is needed. The user approved a same-version OpenMLS
dependency patch on 2026-09-28 to recover genuinely expired historical commits.

Keep signed evidence of accepted admission commits in the encrypted session
record. Save each transition and the resulting local MLS snapshot atomically.
Delivery acknowledgements may finish an admission's retry journal, but cannot
delete the recovery evidence or retained semantic messages. Any admitted
participant holding the evidence may forward it. Verify the original author,
joining device authorization, group id and next epoch before applying it to
a copy of the receiving installation's own MLS state. Install that state only
after the durable transaction succeeds. Never import another client's state.

Probe admitted DM participants for their epoch and text manifest after restart
and periodically while running. This includes the counterpart when the original
desktop is unavailable. Exchange only private authenticated packets. Accept an
older valid roster for a known requester without replacing the newer pinned
roster. Only devices admitted in the locally verified topology can serve or
request recovery. Unrelated users and roster-only devices remain unauthorized.

Apply missing commits in order before declaring epoch recovery complete.
Use issue 25's original text ids, authors, times, bounded batches, UTF-8
fragments and atomic import transactions for missed text. Recovery transfers
have their own packet tags and authorization, so the initial same-user archive
contract stays intact. A changed source starts its own durable manifest cursor;
already imported rows remain deduplicated. Late packets cannot advance a new
source's transfer. Live delivery continues and shares the same message ids.

Persist the active source, transfer id, manifest cursor and observed progress
as optional session membership fields. Reuse `SessionSnapshot.history_sync`
for waiting, importing and completion. Update the existing localized notice
so it refers to an available participant instead of requiring the original
desktop. Completion covers the available source's frozen manifest and current
verified epoch. If every holder of needed data is unavailable, keep waiting.

Retain text and signed commit evidence with the conversation, independently
of delivery receipts. The private recovery protocol separates epoch evidence
from semantic text import. A future hosted storage adapter can supply those
records without owning device keys or replacing the importer.

## Approved scope and test boundaries

The repository requires approval before persisted schemas or public contracts
change. The user approved optional encrypted session membership fields,
private recovery packet variants and the existing history-status semantics
described above.
There are no new Flutter/Rust bridge signatures. The later approved dependency
exception is documented in `docs/Proposals/openmls-historical-validation.md`.

The TDD skill requires confirmed test boundaries. Approved boundaries are:

- Existing public DM and device-link runtimes in independent installation
  processes, using real Moss, OpenMLS and independently keyed stores. Observe
  public snapshots, message metadata and continued bidirectional messaging.
- Existing signed device packet boundary with real keys, MLS and persistence.
  Verify authorization, replay refusal, ordered epoch recovery and restart.
- Existing conversation widget boundary through `test/support/`. Verify
  waiting/importing/completion notices and live text during recovery.

Use the starting commit above as the review baseline. Native missed-epoch
tests may temporarily admit additional real clients solely to create genuine
MLS commits while one of the required installations is offline. They do not
add a product feature or broaden the text-only DM scope.

## Work and checks

- [x] Read issue 26, architecture, ADRs 0029 through 0031 and existing recovery
  limits. Read the previous implementation and its verified test boundaries.
- [x] Confirm persisted fields, protocol scope, test boundaries and baseline.
- [x] Finish baseline Rust build, Moss preparation and Flutter analysis.
- [x] Fail one public-runtime offline/restart text test, then implement recovery.
- [x] Add source switching, concurrent text and unavailable-source coverage.
- [x] Fail real missed-epoch coverage, retain evidence and recover in order.
- [x] Verify cryptographic refusals and durable replay behavior.
- [x] Update localized runtime notices and widget tests.
- [x] Document retention, acknowledgements and MLS ordering with Mermaid.
- [x] Run regular Rust checks and focused native/widget tests.
- [x] Format, build, strict Clippy, Flutter analysis and full suites once at end.
- [x] Measure changed Rust line coverage, at least 80%; branch coverage at
  least 70% if available. Verify bindings remain unchanged.
- [x] Commit and run Standards and Spec reviews through the code-review skill.
- [x] Fix findings within approved scope, verify affected checks and keep clean.
- [x] Resolve expired historical packages after the dependency decision.

## Risks and limits

An available holder of the needed records is required. P2P recovery cannot
reconstruct deleted data or commits discarded by an older runtime before this
feature existed. Retaining records increases the encrypted local store size;
pruning needs a separate policy that accounts for every authorized device.
Semantic import preserves history without creating new delivery receipts.
Windows/macOS runtime validation needs their runners; this workspace is Linux.
Revocation, attachments, groups, calls and mobile background delivery remain
separate tickets. Keep Moss sources unchanged.

The user approved this plan, the persisted fields, private protocol scope,
test boundaries and review baseline on 2026-09-28.

## Verification results

Baseline Rust build, Moss preparation and Flutter analysis passed. The three
existing native history tests and the existing banner widget test passed.
The first returning-device test failed on missing own-device text, then passed
after recovery could import the contact's retained history. A partial import
also passed source loss, recipient restart, source switching and concurrent
live text without repeated rows. The real missed-epoch test failed before the
signed epoch journal was added, then passed with the author off and a restarted
holder relaying the original proof. A second regression failed because the
admission journal waited for every offline device. Admission now finishes
after the joining client and an available counterpart durably acknowledge it;
evidence remains retained. The real five-client scenario passed two missed
epochs, old-client claims after roster extension and continued bidirectional
messaging after recovery. Waiting with all holders off and recovery after one
returns also passed across restart.

Signed packet tests passed admitted/prefix-roster authorization, outsider,
roster-only and wrong-source refusal, changed recipient, stale round, request,
cursor, digest and total, duplicate/conflicting records, forged original author,
wrong group, future epoch and replay. Restart between two genuine epochs
preserves progress. The original-desktop completion regression first returned
no status; it now passes completion and original time/id ordering without an
initial history import.

The localized waiting notice failed its widget assertion before the copy was
generalized to an available participant, then passed. The existing DM screen
test also passes rendering and sending live text in both waiting and importing
states through the approved widget seam. Full Flutter validation
passed 873 tests with five existing platform skips. Flutter analysis and Dart
formatting passed. Bridge generation made no changes. All 25 diagrams in the
architecture and new ADR rendered; the existing feature diagrams also render.
Rust build, strict Clippy and focused runtime/signed packet checks passed.
The final full instrumented Rust suite passed 430 tests: 405 unit tests, eight
device-link flows, two identity tests, one patched-API policy test and fourteen
real-process DM scenarios. Eleven entry points remain ignored, including
isolated workers invoked by their parent tests. No behavioral test was removed.
The unit phase took 381.06 seconds; the independent DM phase took 591.97 seconds.
Logs are under `/tmp/mosh-26-*`.
The separate native Flutter pairing test passed against the rebuilt library.
Two additional runs timed out waiting for the confirmation-code field after
40 seconds, including an isolated run. A later run passed in 26 seconds; the
final original test and harness passed unchanged in 20 seconds. The artifact
selection hypothesis was false: the first executable was already current.
Temporary sorting was reverted. No timeout or product behavior was changed.
The intermittent native UI timeout remains a validation risk outside the DM
recovery slice; the eight independent Rust linking flows all passed.
Final formatting, strict Clippy and Flutter analysis passed. Code generation
and the final drift comparison confirmed unchanged bridge files.

The full Rust run used `cargo llvm-cov show-env --sh`, including independent
installation processes. Focused review-fix tests used the same instrumentation.
Against the fixed point, 645 of 712 changed executable production lines are
covered, or 90.59%. Test code and unchanged vendored upstream code are excluded.
The 11 changed executable lines in the OpenMLS patch all have coverage. The
final measurement includes compiler-mapped derived code and the historical
validation correction; it replaces the earlier 620/635 result. Coverage was
exported without the default workspace filter so the path dependency is
included. JSON and LCOV reports remain under `/tmp/mosh-26-*`.
Stable Rust reports that branch instrumentation requires nightly, unavailable
on this host. Branch coverage is unavailable; region coverage is not used as
branch coverage.

Implementation commit: `ae92a55`, reviewed against `c21b7e1` with independent
read-only Standards and Spec agents. Review-fix commit: `337b514`, verified
with focused initial/recovery signed checks, source switching with live text
and large UTF-8 native transfer. Both agents reviewed that immutable correction
read-only. Standards confirmed both findings resolved, with no new consequential
findings. Spec confirmed P1 resolved, with no new related findings.

## Standards

Final independent read-only review of `c21b7e1...fe805ff`: zero unresolved
findings. Both earlier duplications remain fixed. The guard restores the
calling thread's previous clock; dependency wiring shares OpenMLS 0.8.1 with
the probe. License, provenance and upgrade instructions are documented.

No hard documented-standard breaches; two low-severity duplication findings.
The recovery importer repeated the initial importer's transaction/publication
sequence, and recovery repeated the signed frame-size check. Both now share
the existing history commit/publish owner and device packet ceiling owner.
The affected initial/recovery signed-packet suites passed. Source switching
with live text and large UTF-8 native transfers passed after these fixes.

## Spec

Final independent read-only review of `c21b7e1...fe805ff`: zero findings.
P1 remains resolved. P2 is resolved for v2 evidence, which authenticates the
original admission time before both package validation and local commit
processing. The one changed upstream source and timestamp fields match the
additional user approval. Legacy v1 evidence retains its documented policy.

P1: an equal source manifest or an imported duplicate could mark progress
before the concurrent live row was durable. A crash then lost the row while
the observed source digest prevented reimport. A signed-boundary regression
failed on the missing row after rehydration. Both observation and completion
now commit matching live rows with progress; the regression passes for both
paths, preserving one visible copy and local receipt metadata.

P2: OpenMLS checked historical Add lifetimes against today's clock, including
inside commit processing. The user approved the scoped-clock dependency patch.
OpenMLS 0.8.1 is now vendored with only that source patch. Recovery's v2 evidence
signs the original admission time. After author, roster, group and exact-next-
epoch checks, synchronous validation uses that time and restores the prior
policy on return or unwind. Ordinary admission keeps the actual clock. The
shared decoder enforces the library's acceptable lifetime range; the upstream
predicate requires the application to call it. Legacy evidence without a signed
time retains its v1 signature and actual-clock policy.

The public patched API passes validity boundaries, nested scopes, panic cleanup
and thread isolation. The signed seam first failed a genuine 100-day-old
package/commit, then passed recovery, restart and bidirectional MLS messages.
It refuses forged/out-of-window/future times, tampered package/commit signatures
and excessive lifetime ranges. Strict Clippy, core build and Flutter analysis
pass. Final independent review has no unresolved findings. Code generation
passed without binding changes. The full Rust rerun passed and changed
production coverage is 90.59%, including 100% of the patched upstream lines.

The separate probe check exposes a pre-existing E0603: `mosh-probe/src/main.rs`
imports `PrivateGroupRuntime`, whose core re-export is crate-private. Neither
source differs from the review baseline. Probe resolution correctly selects
the patched OpenMLS; its lockfile only drops that crate's registry/checksum.
The unrelated visibility failure remains outside issue 26.

The implementation and corrections are local commits on `main`, including
`ae92a55`, `337b514` and `fe805ff`. No push, deployment or merge was performed.

Review findings: Standards 0 unresolved; Spec 0 unresolved. Earlier Standards
2 and Spec 2 are fixed and independently reviewed.

## Changed files

- `dm-offline-recovery.plan.md`
- `docs/ADR/0032-dm-offline-recovery.md`
- `docs/Architecture.md`
- `docs/Features/private-dm.md`
- `docs/Proposals/openmls-historical-validation.md`
- `docs/Proposals/openmls-historical-validation.patch`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ru.arb`
- `mosh-core/src/private_dm_runtime.rs`
- `mosh-core/Cargo.toml`
- `mosh-core/Cargo.lock`
- `mosh-core/src/mls_crypto.rs`
- `mosh-core/src/private_dm_runtime/devices/admission.rs`
- `mosh-core/src/private_dm_runtime/devices/authorization_tests.rs`
- `mosh-core/src/private_dm_runtime/devices/history/fragments.rs`
- `mosh-core/src/private_dm_runtime/devices/history/import.rs`
- `mosh-core/src/private_dm_runtime/devices/history/mod.rs`
- `mosh-core/src/private_dm_runtime/devices/history/packet_tests.rs`
- `mosh-core/src/private_dm_runtime/devices/history/packet_tests/recovery.rs`
- `mosh-core/src/private_dm_runtime/devices/history/packet_tests/recovery/historical.rs`
- `mosh-core/src/private_dm_runtime/devices/history/source.rs`
- `mosh-core/src/private_dm_runtime/devices/mod.rs`
- `mosh-core/src/private_dm_runtime/devices/proof.rs`
- `mosh-core/src/private_dm_runtime/devices/recovery/epochs.rs`
- `mosh-core/src/private_dm_runtime/devices/recovery/import.rs`
- `mosh-core/src/private_dm_runtime/devices/recovery/mod.rs`
- `mosh-core/src/private_dm_runtime/devices/recovery/source.rs`
- `mosh-core/src/private_dm_runtime/devices/recovery/types.rs`
- `mosh-core/src/private_dm_runtime/devices/runtime.rs`
- `mosh-core/src/private_dm_runtime/devices/types.rs`
- `mosh-core/src/private_dm_runtime/session.rs`
- `mosh-core/tests/dm_recovery/mod.rs`
- `mosh-core/tests/multi_device_dm_flow.rs`
- `mosh-core/tests/historical_lifetime.rs`
- `mosh-probe/Cargo.lock`
- `test/features/conversation/dm_history_banner_test.dart`
- `test/features/conversation/dm_screen_test.dart`
- `third_party/openmls/` retains 244 upstream crate files plus the upstream MIT
  license and `MOSH-PATCH.md`. Only `src/key_packages/lifetime.rs` changes.
