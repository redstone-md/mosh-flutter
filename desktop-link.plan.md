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
- [ ] 9. Add the Devices settings section, Riverpod polling, QR image import
  and approval/error UI in English and Russian. Verify QR round-trip, analyzer
  and screen actions using the real native bridge where supported.
- [ ] 10. Run final full Rust/Flutter suites, focused independent-process
  pairing proof and coverage. Changed production code needs 80% line coverage
  and 70% branch coverage when available. Run available stack quality gates.
- [ ] 11. Apply implement's code-review skill against the starting commit,
  standards and issue 23. Reviewers are read-only; fix actionable findings and
  rerun affected checks. Apply unslop to docs and user copy.
- [ ] 12. Update this plan with actual evidence and remaining platform limits,
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

- Rust build, formatting and Clippy with `-D warnings` pass.
- A fresh bridge generation followed by Rust formatting changes no generated
  file. Existing bridge signatures are compatible.
- All 870 Flutter tests pass, with the five existing skips. Analyzer is clean
  and Dart formatting changes no files.
- Six independent-process Moss flows and two encrypted identity tests pass.
  Three protocol tests prove signatures, tampering and expiry at byte boundaries.
- LLVM line coverage for the new Rust feature and its bridge is about 90%.
  Coverage uses the real-process tests, including the public bridge, and the
  protocol tests. The stable Rust toolchain and Flutter LCOV do not emit branch
  coverage here.
- Mermaid CLI renders all six device-link diagrams successfully.

The first native UI rerun overlapped cargo rebuilding its peer executable.
It failed before starting that peer. Run native verification after cargo
finishes, as CI does, then record its final result and Flutter coverage.
The initial atomic feature commit pins the reviewers' diff to the starting
commit. A final commit will record their findings, fixes and completed checks.

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
  the actual listen_port from Moss. All six scenarios now pass together.
