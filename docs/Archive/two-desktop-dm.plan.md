# Two-desktop DM plan

Chosen direction: [brainstorm](two-desktop-dm.brainstorm.md).
Spec: https://github.com/redstone-md/mosh-flutter/issues/24.
Review fixed point: `b2145bdc9629ea4cb7c3442e271f9db90da3cb93`.

## Goal and scope

Two linked desktops exchange new text in one existing DM with one counterpart.
The original may be off. Each installation owns separate MLS and transport
keys. Preserve one conversation, contact name, invite address and fingerprint.
Scope and exclusions are in the brainstorm. No dependency, table or public
bridge changes are planned. Compatible fields in the encrypted record carry
membership and admission state.

## Ordered work and done criteria

- [x] Read issue 24, its closed blocker 23, architecture, local guidance and
  relevant ADRs. Inspect real-process tests and OpenMLS documentation.
- [x] Establish the full baseline after preparing this plan. Run
  `node scripts/moss-prepare.mjs`, `cargo build --manifest-path mosh-core/Cargo.toml`,
  `cargo test --manifest-path mosh-core/Cargo.toml`, `flutter analyze` and
  `flutter test`. Track every failure below with a root cause and fix path.
- [x] Correct the stale fingerprint explanation in the architecture map and
  add the device admission boundaries before implementation.
- [x] Write one failing real-process test for joining a linked desktop to an
  existing DM and receiving counterpart text on both devices. Implement
  verified identity binding, private offers and independently keyed admission.
  Run that test and typecheck with `cargo check`.
- [x] Add durable admission state and atomic session/MLS writes. Test the
  pending join and approval delivery across independent process restarts.
  Reuse the same Commit and Welcome on retry and reject wrong authorization.
- [x] Add a failing test for sender-device sync, original offline and reply
  from the linked device. Implement authorized live fan-out and canonical
  author display. Verify message ids and counterpart delivery receipts.
- [x] Add simultaneous sends, duplicate delivery and restart continuation to
  the real flow. Test outsiders, changed signed metadata and roster rollback
  through the cryptographic admission contract with real keys and storage.
- [x] Prove the same flow through public bridge calls and default Moss
  discovery. Verify that each installation lists exactly one DM and that the
  fingerprint is unchanged. Run related single-device and device-link tests.
- [x] Update private-DM docs, glossary and ADR with Mermaid diagrams,
  admission trust rules, epoch persistence and explicit privacy limits.
- [x] Run the final validation in the order below. Measure changed Rust code
  coverage with the real-process flow; require 80% lines and 70% branches
  where branch measurement is supported. Address uncovered failure paths.
- [x] Commit atomic changes on the current branch. Run the implement skill's
  two-axis code-review against the fixed point. Fix actionable findings,
  rerun affected checks and commit corrections. Verify a clean working tree.

## Baseline failures

No baseline failures. Rust: 396 unit tests plus 10 integration tests passed,
with seven existing ignored tests. Flutter: 870 tests passed with five existing
platform skips. Native build and Flutter analyzer passed. Logs are temporary
under `/tmp/mosh-24-*`. The first new three-process test failed at the missing
linked-desktop DM, as expected, before implementation.

## Findings addressed during implementation

- [x] In-flight two-party text had old-epoch ciphertext after admission.
  Re-encrypt it at the current epoch while preserving its message id.
- [x] The default-discovery scenario could lack a room-gossip route during
  bootstrap. Use the existing directed stream for a reachable contact, with
  the existing gossip fallback.
- [x] The early flow assertion sent text before the contact accepted the new
  epoch. Wait for an authenticated connected state before asserting live text.
  Historical transfer remains issue 25.
- [x] The paused-contact receipt test initially left the two-party handshake
  unserviced. Drive both real runtimes to connected before pausing the contact.
- [x] Retain retry targets for every admitted device. A sibling receipt does
  not claim contact delivery; a contact receipt updates both desktops.
- [x] Reloading the device identity must not save a stale roster. Atomically
  initialize once and make subsequent reads read-only. Concurrent initializers
  return the same stored winner.
- [x] Clear a stale signing key if current device identity validation fails.
  Pending device joins accept only the signed admission Welcome.
- [x] `a_lost_hello_keeps_the_inviter_handshaking` failed in final regression.
  The new bootstrap stream path also applied to sessions without device
  membership. Restrict it to device-enabled sessions, then rerun this test
  and the full Rust suite. Existing test assertions remain unchanged.

The same unscoped bootstrap path caused the following failures. Each keeps
its original assertions and is verified through its related test module.

- [x] `a_failed_stream_is_not_retried_for_every_chunk`: extra stream attempts.
  Apply the device-membership guard, rerun blob route tests.
- [x] `a_relayed_peer_gets_its_chunks_over_the_room_wire`: extra stream sends.
  Apply the same guard, rerun blob route tests.
- [x] `a_refused_publish_leaves_the_text_queued_not_failed`: Sent instead of
  Queued. Apply the same guard, rerun outbox tests.
- [x] `unacked_sent_message_auto_resends_then_gives_up`: a refused publish
  counted as a resend. Apply the same guard, rerun outbox tests.
- [x] `a_call_offer_failure_frees_the_call_slot`: publish failure was bypassed.
  Apply the same guard, rerun state tests.
- [x] `a_failed_accept_goes_back_to_ringing_for_the_retry`: publish failure was
  bypassed. Apply the same guard, rerun state tests.
- [x] `a_failed_decline_keeps_the_call_for_a_retry`: publish failure was bypassed.
  Apply the same guard, rerun state tests.
- [x] `a_refused_receipt_is_resent_on_the_next_viewed`: a refused receipt was
  sent through the stream. Apply the same guard, rerun state tests.
- [x] Native Flutter pairing approval timed out while native regression tests
  were active. The canonical sequential run passed in 24 seconds. Keep native UI checks
  after Cargo tests so their LAN discovery environments do not overlap.

## Testing methodology

The primary proof uses three separate operating-system processes. Each has a
real Moss node, separate signing keys, a separate encrypted redb database and
its own OpenMLS provider. Start with a real existing DM, then use the approved
QR pairing flow. Observe snapshots and session lists through public runtime
methods. Test both active devices, own-device echo, the original switched off,
simultaneous sends and messages after restart. Assert exactly one row per id,
one contact name and the existing fingerprint. Use real cryptographic inputs
for refusal and tamper checks. Never add doubles to conceal network behavior.

The existing Flutter suite covers the unchanged snapshot rendering and bridge
callers. The public bridge scenario also uses independent processes and the
default discovery configuration. Focus each TDD cycle on one caller-visible
flow. Run single test files during implementation; run the full relevant suites
at the baseline and once at final validation.

## Constraints and risks

- Keep Moss sources, the sibling historical application and build artifacts
  out of changes and commits.
- Keep the session and MLS snapshot in one database transaction for admission.
  Preserve independent sender ratchets across restarts.
- Verify the counterpart's roster through the established MLS identity.
  A self-signed outsider roster alone never grants admission.
- Admission retries are idempotent. Lost Commit/Welcome must not create a
  second leaf or make one installation silently advance alone.
- Issue 26 handles missed epochs and offline catchup. Issue 25 handles old
  history. They must not be fabricated as completed here.
- Native desktop packaging is platform-dependent. This host is Linux;
  record any unavailable Windows/macOS validation explicitly.

## Final validation order

1. TDD skill: real public-runtime flows and focused refusal tests must pass.
2. Unslop skill: remove vague wording from docs and user-facing reports.
3. `cargo fmt --manifest-path mosh-core/Cargo.toml --check` and
   `cargo clippy --manifest-path mosh-core/Cargo.toml --all-targets -- -D warnings`.
   Formatting and strict Rust type/lint checks.
4. `cargo build --manifest-path mosh-core/Cargo.toml` then
   `cargo test --manifest-path mosh-core/Cargo.toml`. Full Rust regression proof.
5. `cargo llvm-cov` scoped to changed modules and the real-process tests.
   Confirm meaningful execution coverage rather than implementation mirrors.
6. `flutter analyze`, `flutter test` and native bridge tests available here.
   Preserve the shell and real bridge behavior.
7. Regenerate bindings using the CI flags, format Rust, and inspect drift.
   The public contract must remain unchanged.
8. Code-review skill: separate Standards and Spec reviews of the final commits.
   Review agents have read-only ownership and must not edit files.
9. `git diff --check`, verified Conventional Commit subjects and clean status.
   Deliver the change with changed files, simplifications and remaining risks.

## Final verification

The final build and full Rust suite passed after the review correction.
All 418 tests passed: 402 unit tests, eight device-link flows, two identity
tests and six three-process DM scenarios. Eight tests remain ignored,
including the new independent-process worker entry point required by the
existing harness. No behavioral test was skipped to make the suite pass.

Final Flutter validation passed 870 tests with five existing platform skips.
The rebuilt native library also passed the real Flutter bridge pairing test
after the Rust suite, in 19 seconds. Analyze, strict Clippy, localization
generation, Rust formatting and binding drift checks passed. All 29 Mermaid
diagrams in the changed docs rendered as SVG.

The first final Rust run found nine legacy carrier regressions. The membership
guard fixed all nine. Their related 39 tests and the full suite passed with
the original assertions. The review's stopped-contact regression first failed
on sibling typing, then passed after the authenticated-contact check.

The final full Rust run used the environment from `cargo llvm-cov show-env`,
so coverage includes the real independent processes. JSON and LCOV reports
cover 1,260 of 1,326 changed executable production lines, or 95.02%. Each
changed production file with measured lines exceeds 80%. New device modules
range from 90.22% to 100%; the new persistence module reaches 93.02%. Test
code is excluded from this calculation. Stable Rust cannot measure branches;
`cargo llvm-cov --branch` reports that nightly is required. The 70% branch
gate therefore does not apply on this host. Region coverage is not reported
as branch coverage.

Windows and macOS app builds and installer packaging require their platform
runners and were unavailable on this Linux host. History, missed-epoch
catchup and revocation remain issues 25, 26 and 27 respectively.

The implementation and review correction are committed as `3f40ed4` and
`efe9b07`. The final documentation commit records these checks and the
separate review outcomes below. Verify its Conventional Commit subject,
`git diff --check` and clean status before delivery.

## Standards

Initial review of `3f40ed4`, read-only Standards agent:

- P2, contact-control boundary remains two-member-only. `route_device_frame`
  sends controls to every other MLS client, but `TypingIndicator` treats a
  sibling as counterpart activity. Decryption discards the authenticated
  signer. A sibling typing while the contact is offline shows contact typing
  and can move the session to Connected. ReadReceipt has the same identity
  omission; PeerAnnounce can replace the contact peer id with a sibling's.
  This conflicts with root Code and Design requirements for explicit
  boundaries and ADR 0030's distinction between own-device and counterpart
  activity. Authenticate these controls against the MLS signer, ignore sibling
  activity and prove this with a real three-process test.
- Baseline smell, repeated ownership decisions. The text path, Hello and
  delivery receipts distinguish own user from counterpart independently,
  while other controls retain older assumptions. A shared authenticated-contact
  helper would keep this rule consistent.

No additional consequential documented-standard violations found. Documented
exceptions cover the existing large owners and end-to-end test functions.

## Spec

Initial review of `3f40ed4`, read-only Spec agent:

- P2, sibling controls still count as contact activity. Spec: "В существующем
  DM собеседник видит одного пользователя и один контактный адрес."
  Fanout sends controls to siblings, but control handling treats every
  different participant as counterpart. Typing on Original makes Linked show
  counterpart typing and refreshes contact liveness. Read receipts also
  refresh it; PeerAnnounce can replace the stored contact peer id. Resolve the
  authenticated signer for typing/read controls, ignore own-client contact
  effects and prevent sibling announcements from replacing the contact
  address. Prove this with the counterpart stopped.

No other missing requirements or scope creep found. Separate authorized MLS
keys, stable conversation identity, fanout, own-device echo, simultaneous
sends, primary-off operation, restart, real-process proof and privacy docs
are represented. Excluded history, missed-epoch recovery, revocation and
non-text features remain excluded. Full-suite verification was pending.

Initial findings: Standards has one boundary defect and one ownership smell.
Spec has one defect. Both axes identify sibling contact effects as their
worst issue.

## Review fix and verification

- [x] Reproduce sibling typing changing an offline contact to Connected with
  three real processes and isolated per-installation receipt settings.
- [x] Add one authenticated-contact helper for Hello, typing and read receipts.
  Keep sibling delivery receipts separate and reject legacy address hints
  after verified multi-client admission.
- [x] Verify real contact typing and read receipts reach both desktops, while
  sibling typing/read activity cannot restore the stopped contact's liveness.
- [x] Ask both read-only reviewers to check the correction.
- [x] Run the final full Rust suite and coverage after the review fix. The
  preceding full run passed 402 unit and 15 integration tests, with eight
  existing or required subprocess ignores. Do not repeat the unchanged full
  Flutter suite; rebuild and run the native Flutter bridge check sequentially.

Both follow-up reviewers accepted `efe9b07`. Standards reported the shared
contact check and real-process test resolve its boundary finding and ownership
smell, with no remaining consequential standards findings. Spec reported the
contact address, sender authentication and offline-control regression resolve
its finding, with no remaining issue 24 gaps or scope creep. Neither reviewer
ran native tests or changed files. The final full suite and coverage now pass.

Final findings: Standards has zero remaining findings. Spec has zero remaining
findings. The sibling contact-control defect identified by each axis is fixed.
