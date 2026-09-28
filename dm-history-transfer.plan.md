# Linked desktop DM history, issue 25

Spec: https://github.com/redstone-md/mosh-flutter/issues/25.
Review fixed point: `5c11d8062811f158ef34046c9aea491454e66afe`.
Commit on the current branch. No push or deployment.

## Scope and design

Import the existing DM's text after independent MLS device admission. Reuse
the private signed device packets and encrypted directed Moss stream. Only
admitted devices in the same verified user roster may request or import it.
Keep each device's signing keys, local storage key and MLS state independent.

Transfer semantic records with message id, original author, original send
time and text. Skip attachments and call events. Freeze an ordered manifest
of source history keys when a transfer starts. Batch requests carry a stable
transfer id and cursor. The source persists the manifest; the recipient saves
each batch and its cursor atomically under its own storage key. Replayed
batches and live text share id-based deduplication. Conflicting copies fail
closed. Live sends continue during import.

The encrypted session record gains optional import/export progress, with no
new table or dependency. The only proposed public contract change is an
optional typed history status in `SessionSnapshot`. Its states are waiting
for a source, importing and complete. The conversation displays runtime
waiting/importing status and hides the banner after durable completion.
No new bridge operation or gateway method is needed.

## Test boundaries

- Existing public DM/device-link runtime and independent-process runner,
  with real Moss, OpenMLS and separately keyed redb stores. Observe public
  snapshots and session lists. Cover pre-link history, live text during
  import, disconnect, restart, repeated batches and unavailable sources.
- Existing conversation widget boundary using `test/support/`. Observe the
  waiting/importing banner and its disappearance after completion.
- Existing signed device packet authorization boundary with real keys and
  stores. Refuse outsiders, counterparts, altered records and stale progress.

The user approved the contract additions and these test boundaries on
2026-09-28. Keep subsequent work within this scope.

## Work and checks

- [x] Read issue, architecture, ADRs 0029/0030 and existing runtime boundaries.
- [x] Build the unchanged Rust core and prepare Moss.
- [x] Confirm the proposed contract additions and test boundaries.
- [x] One failing real-process import test, then the smallest complete flow.
- [x] Durable cursor/manifest, interruption and live-message deduplication.
- [x] Authorization/refusal and runtime waiting status, then UI coverage.
- [x] Update architecture and add history protocol documentation with Mermaid.
- [x] Regular `cargo check` and focused native/widget tests.
- [x] Format, strict Clippy, build, full Rust and Flutter suites once at end.
- [x] Measure changed Rust line coverage, at least 80%; branch coverage at
  least 70% if this toolchain supports it. Run bridge codegen and drift check.
- [x] Commit and run independent Standards/Spec code-review agents read-only.
  Fix findings, verify affected checks and keep the working tree clean.

## Risks

History is trusted semantic content from an authorized sibling. Import does
not recreate the old MLS decryption state or attest new delivery receipts.
Completion covers the frozen source manifest. Offline message and missed-epoch
recovery belongs to issue 26. Windows/macOS runtime validation requires their
platform runners; this workspace is Linux. Keep Moss sources unchanged.

## Verification results

Starting Rust build and Moss preparation passed. The existing three-process
linked-desktop DM test, Flutter analyzer and conversation banner tests passed.
Logs are temporary files under `/tmp/mosh-25-baseline-*`.
The first pre-link-history test failed on the missing old text, then passed
with its original id/author/time assertions. The interrupted transfer test
passed source loss, live text during import, partial progress and restart.
The large UTF-8 text test exposed Moss's 64 KiB framed payload ceiling. Bounded
fragments now preserve the entire message across transfer and restart.

Signed packet refusals passed with independent keys, real Moss and redb,
including partial-message recovery after restart. Waiting/importing/completion
widget tests passed alongside the existing conversation notice tests. Regular
`cargo check` and Flutter analysis passed. All 29 Mermaid diagrams in the
changed architecture, feature documentation and ADR rendered as SVG.

Final build and full Rust validation passed 422 tests: 403 unit tests, eight
device-link flows, two identity tests and nine three-process DM scenarios.
Nine test entry points remain ignored, including isolated workers invoked
by their parent tests. No behavioral test was removed to pass validation.
Flutter passed 871 tests with five existing platform skips. The separate
native Flutter pairing test passed against the rebuilt library.

Strict Clippy, final Flutter analysis and formatting checks passed. Bridge
generation produced identical hashes for all five changed generated files.
All logs are temporary files under `/tmp/mosh-25-*`.

The full Rust run used `cargo llvm-cov show-env --sh`, so the JSON and LCOV
reports include the independent installation processes. Against the fixed
point, 428 of 495 changed executable production lines were covered, or
86.46%, including 52 generated bridge lines. New history modules range from
93.33% to 100%; the new atomic persistence helper reaches 100%. Test code is
excluded. Stable Rust reports that `--branch` requires nightly, unavailable
on this host. The branch gate does not apply; region coverage is not used as
branch coverage.

Implementation commit: `f522549`, `feat(dm): import text history on linked
desktops`. The final documentation commit records the independent reviews
below. Both reviewers used `git diff 5c11d806...f522549`, read only and did not
rerun tests or change files.

## Standards

0 findings. No consequential documented-standard violations or actionable
baseline smells found in `5c11d806...f522549`.

History concerns stay in feature-local modules, reuse existing
transport/storage/UI components, and preserve serialized runtime and
transaction ownership. Contract additions match the recorded approval.
ADR 0031 documents the relevant size exceptions.

## Spec

No Spec findings. Commit `f522549` matches issue 25 and the approved initial
two-desktop text-history scope.

Authorization, original message metadata, independent storage encryption,
resumable progress, live-message deduplication, runtime notices and Mermaid
documentation are implemented. Offline epoch recovery and revocation remain
correctly deferred to issues 26 and 27.

Final findings: Standards 0; Spec 0. Neither axis has a remaining issue.

## Changed files

- `dm-history-transfer.plan.md`
- `docs/ADR/0031-linked-desktop-dm-history.md`
- `docs/Architecture.md`
- `docs/Features/private-dm.md`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ru.arb`
- `lib/src/features/conversation/conversation_banners.dart`
- `lib/src/rust/frb_generated.dart`
- `lib/src/rust/frb_generated.io.dart`
- `lib/src/rust/frb_generated.web.dart`
- `lib/src/rust/private_dm_runtime/contracts.dart`
- `mosh-core/src/frb_generated.rs`
- `mosh-core/src/persistence.rs`
- `mosh-core/src/persistence/dm_devices.rs`
- `mosh-core/src/persistence/dm_history.rs`
- `mosh-core/src/private_dm_runtime.rs`
- `mosh-core/src/private_dm_runtime/contracts.rs`
- `mosh-core/src/private_dm_runtime/devices/admission.rs`
- `mosh-core/src/private_dm_runtime/devices/authorization_tests.rs`
- `mosh-core/src/private_dm_runtime/devices/history/fragments.rs`
- `mosh-core/src/private_dm_runtime/devices/history/import.rs`
- `mosh-core/src/private_dm_runtime/devices/history/mod.rs`
- `mosh-core/src/private_dm_runtime/devices/history/packet_tests.rs`
- `mosh-core/src/private_dm_runtime/devices/history/records.rs`
- `mosh-core/src/private_dm_runtime/devices/history/source.rs`
- `mosh-core/src/private_dm_runtime/devices/history/types.rs`
- `mosh-core/src/private_dm_runtime/devices/mod.rs`
- `mosh-core/src/private_dm_runtime/devices/runtime.rs`
- `mosh-core/src/private_dm_runtime/devices/types.rs`
- `mosh-core/src/private_dm_runtime/session.rs`
- `mosh-core/src/private_dm_runtime/snapshot.rs`
- `mosh-core/tests/dm_history/mod.rs`
- `mosh-core/tests/link_support/api.rs`
- `mosh-core/tests/link_support/mod.rs`
- `mosh-core/tests/multi_device_dm_flow.rs`
- `native_test/support/native_peer.dart`
- `test/features/conversation/dm_history_banner_test.dart`
- `test/support/message_builders.dart`
