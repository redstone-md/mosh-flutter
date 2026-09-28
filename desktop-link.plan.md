# Desktop linking plan

Chosen direction: [brainstorm](desktop-link.brainstorm.md).
Spec: https://github.com/redstone-md/mosh-flutter/issues/23.
Starting commit: 67e18d0. Commit on the current branch; do not push or deploy.

## Goal and boundaries

Implement issue 23 through a device-link feature in Rust and Flutter.
Include QR creation/import, user and device ids, approval, signed roster,
encrypted persistence, restart and real Moss verification. Preserve DM data.
Exclude messaging/history sync, revoke, wallet, device caps and mobile work.

The ticket already specifies the installation-level test seam. Test the real
runtime public operations and snapshots in independent processes with separate
redb stores and real Moss, plus the Flutter screen through the real bridge.
Use no new service doubles. QR encoding/decoding gets a real round-trip test.

## Ordered work

- [x] 1. Read architecture, identity/storage/transport decisions and issue.
- [x] 2. Choose the protocol and prepare this plan before implementation.
- [x] 3. Review the additive bridge contract, new encrypted table and QR
  packages with the user as required by AGENTS.md. Continue baseline and
  internal design work while the review is pending.
- [x] 4. Prepare Moss, run cargo build then the full Rust and Flutter test
  baseline. Record each existing failure below and fix only applicable causes.
- [x] 5. Add module guidance, ADR/glossary/architecture contracts. Define
  signature context, admission, expiry, replay and crash recovery precisely.
- [x] 6. Write a failing public-runtime persistence/identity test. Implement
  encrypted device state and signed authorization chain. Prove restart,
  unchanged Moss identity/history, tampering and unauthorized signer rejection.
- [x] 7. Write a failing real-Moss pairing test. Implement encrypted stream
  protocol, trusted approval, acknowledgement and retry. Extend one flow at a
  time for refusal, code mismatch, expiry, replay and interrupted connections.
- [x] 8. Add thin bridge functions and regenerate bindings. Run cargo build,
  clippy and bridge generation drift check. Preserve all existing signatures.
- [x] 9. Add the Devices settings section, Riverpod polling, QR image import
  and approval/error UI in English and Russian. Verify QR round-trip, analyzer
  and screen actions using the real native bridge where supported.
- [x] 10. Run final full Rust/Flutter suites, focused independent-process
  pairing proof and coverage. Changed production code needs 80% line coverage
  and 70% branch coverage when available. Run available stack quality gates.
- [x] 11. Apply implement's code-review skill against the starting commit,
  standards and issue 23. Reviewers are read-only; fix actionable findings and
  rerun affected checks. Apply unslop to docs and user copy.
- [x] 12. Update this plan with actual evidence and remaining platform limits,
  commit atomically with Conventional Commits, verify subject and clean tree.

## Baseline failures

Rust baseline: 393 passed, 6 pre-existing ignored, 0 failed. Build passed.
Flutter baseline: 859 passed, 5 pre-existing skipped, 3 loading failures.
All three share stale ignored localization output, missing transportMesh.
Regenerated with flutter gen-l10n; focused rerun passes all 9 tests.

- [x] desktop_app_relauncher_test.dart loading failure, regenerated l10n.
- [x] lifecycle_gate_test.dart loading failure, regenerated l10n.
- [x] mobile_rail_back_test.dart loading failure, regenerated l10n.

## Verification methodology

Run new tests red before implementation, then green through public methods.
Independent processes are required because Moss keystore/inbox state is
process-global. Each process has its own DEK, database and node. Inspect user
ids, device descriptors, roster snapshots and existing DM text after reload.
The linking test must fail when approval, signature, expiry or persistence
checks are removed. Assert no addition after failed requests. Preserve real
DM handshake/send/restart tests as compatibility evidence.

Final order: Rust build, focused tests, full Rust suite, cargo fmt check,
clippy with -D warnings, codegen plus drift check, Flutter localization,
dart format check, flutter analyze, focused QR/UI verification, full Flutter
suite, coverage, code-review, fix/rerun, git diff --check and commit.

## Constraints

No edits inside moss or sibling repositories. No private keys or QR secrets
in bridge snapshots except the QR text needed by the initiating screen.
Do not expose network address/port inputs. No unrelated test refactors.
Windows/macOS packaging requires those hosts; document unavailable platform
checks, and use the Linux host for real native/bridge/runtime evidence.

## Validation evidence

- Rust build, formatting and Clippy with `-D warnings` pass. The final full
  suite passes 406 tests, with six existing ignored tests. The additional
  ignored process entry is deliberately spawned by the eight flow tests.
- A fresh bridge generation followed by Rust formatting changes no generated
  file. Existing bridge signatures are compatible.
- All 870 Flutter tests pass, with the five existing skips. Analyzer is clean
  and Dart formatting changes no files.
- The actual native Flutter approval flow and two QR image tests pass.
  New Flutter feature line coverage is 87.88%, or 174 of 198 lines.
  Each feature file exceeds 80%; the lowest is 81.82%.
- Eight independent-process Moss flows and two encrypted identity tests pass.
  Three protocol tests prove signatures, tampering and expiry at byte boundaries.
- LLVM line coverage for the new Rust feature and its bridge is 91.30%,
  or 882 of 966 measured lines.
  Coverage uses the real-process tests, including the public bridge, and the
  protocol tests. The stable Rust toolchain and Flutter LCOV do not emit branch
  coverage here.
- Mermaid CLI renders all six device-link diagrams successfully.

Run native UI verification after cargo finishes, as CI does. An earlier run
overlapped rebuilding its peer executable and failed before starting the peer.
The final sequential run passes. Windows/macOS packaging cannot run on this
Linux host; their existing CI lanes must prove those platform builds.

Coverage commands, run sequentially after the full Rust suite:

```sh
cargo llvm-cov test --manifest-path mosh-core/Cargo.toml --test device_link_flow --test device_link_identity --json --output-path /tmp/mosh-link-rust-coverage.json
cargo llvm-cov test --manifest-path mosh-core/Cargo.toml --no-clean --lib --json --output-path /tmp/mosh-link-rust-coverage.json device_link::protocol_tests
flutter test --coverage native_test/device_link_test.dart test/features/device_link/qr_image_test.dart
```

The Rust report counts feature and bridge files, excluding test and generated
code. Flutter uses its LCOV report for the six feature files. Generated reports
stay outside version control. The feature and two review-fix commits preserve
the reviewed changes; this final documentation commit records the checks.

## Review findings and fixes

- [x] Becoming ineligible after Ready cleared only the joining desktop.
  The real-process DM-during-pairing test failed with the trusted desktop still
  awaiting approval. Share cancellation's signed rejection path after saving
  terminal state. The test now proves rejection, refusal of the old code and
  no addition while preserving the joining desktop's identity and DM.
- [x] Cancelled QR replay after disconnect. The real-process regression failed
  because cancellation forgot the request after a best-effort packet. Save
  consumed ids until expiry in the encrypted row before rejecting or approving.
  Prove that reimport fails even after both processes restart.
- [x] A DM started during pairing made a saved request ineligible and prevented
  runtime construction. The real-process regression failed with InvalidRoster.
  Separate valid identity loading from changing admission eligibility; clear
  the pending request while preserving identity and real DM data.
  Both regression tests now pass in the eight-scenario real-Moss suite.
- [x] Prevent an older poll from replacing an action result. Invalidate snapshots
  started before or during an action with an action revision.
- [x] Document a scoped exception to ADR 0025 for the five feature-owned bridge
  calls. Keep real native verification and avoid widening the scripted facade.
- [x] Isolate real network scenarios from each other's LAN discovery traffic.
  Installations inside each scenario still run as independent processes.
  Default discovery gets a 60-second bound to cover the 12-second bootstrap
  timeout and 15-second announcement intervals. Register each priority target
  once, then let Moss's own handshake maintenance retry it; packet retries
  no longer launch a new handshake every 500 ms.

The standards and spec reviewers rechecked the fixes and report no unresolved
actionable findings. Unslop review kept the docs and user copy in plain language.

## Recovery findings

- [x] Restart during delivery originally left the joining desktop Idle.
  The failing independent-process test reproduced this. Save its authenticated
  QR, trusted device and base roster before Ready; restore it until expiry.
  The test now passes after both desktops restart.
- [x] A successful transport write could conceal a disconnected peer.
  Report ConnectionLost after 15 seconds without an authenticated response;
  delivery completes only after the signed durable-save acknowledgement.
- [x] A dense QR at a fixed 300-pixel size could not be decoded. Its renderer
  rounded modules to fractional pixel positions. Render whole pixel modules
  and round the left offset; the real widget image now round-trips at 300 pixels.
  Normalize malformed image decoder errors to the localized invalid-QR message.
- [x] A concurrent real-process test could dial the wrong port after Moss
  fell back from an occupied requested port. Use OS-assigned ports and read
  the actual listen_port from Moss. All eight scenarios now pass together.

## Changed files

- `.github/workflows/ci.yml`
- `AGENTS.md`
- `CONTEXT.md`
- `desktop-link.brainstorm.md`
- `desktop-link.plan.md`
- `docs/ADR/0029-private-desktop-device-linking.md`
- `docs/Architecture.md`
- `docs/Features/device-linking.md`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ru.arb`
- `lib/src/features/device_link/device_link_copy.dart`
- `lib/src/features/device_link/device_link_provider.dart`
- `lib/src/features/device_link/device_link_qr.dart`
- `lib/src/features/device_link/device_list.dart`
- `lib/src/features/device_link/devices_settings_section.dart`
- `lib/src/features/device_link/qr_image.dart`
- `lib/src/features/settings/settings_screen.dart`
- `lib/src/rust/api/device_link.dart`
- `lib/src/rust/device_link/types.dart`
- `lib/src/rust/frb_generated.dart`
- `lib/src/rust/frb_generated.io.dart`
- `lib/src/rust/frb_generated.web.dart`
- `mosh-core/AGENTS.md`
- `mosh-core/src/api/device_link.rs`
- `mosh-core/src/api/mod.rs`
- `mosh-core/src/device_link/identity.rs`
- `mosh-core/src/device_link/mod.rs`
- `mosh-core/src/device_link/protocol_tests.rs`
- `mosh-core/src/device_link/qr.rs`
- `mosh-core/src/device_link/roster.rs`
- `mosh-core/src/device_link/runtime/actions.rs`
- `mosh-core/src/device_link/runtime/mod.rs`
- `mosh-core/src/device_link/runtime/receive.rs`
- `mosh-core/src/device_link/runtime/service.rs`
- `mosh-core/src/device_link/transport.rs`
- `mosh-core/src/device_link/types.rs`
- `mosh-core/src/device_link/wire.rs`
- `mosh-core/src/frb_generated.rs`
- `mosh-core/src/lib.rs`
- `mosh-core/src/moss_ffi.rs`
- `mosh-core/src/persistence.rs`
- `mosh-core/tests/device_link_flow.rs`
- `mosh-core/tests/device_link_identity.rs`
- `mosh-core/tests/link_support/api.rs`
- `mosh-core/tests/link_support/dm.rs`
- `mosh-core/tests/link_support/mod.rs`
- `native_test/device_link_test.dart`
- `native_test/support/native_peer.dart`
- `pubspec.lock`
- `pubspec.yaml`
- `test/features/device_link/qr_image_test.dart`
