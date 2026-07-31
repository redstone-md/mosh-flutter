# flutter-rewrite.plan.md

Working plan for rewriting the Mosh application shell under Flutter inside a
sandboxed fork. Produced at the end of the `/grill-with-docs` session; the
decisions it depends on live in ADRs 0009-0015 and `docs/flutter-fork-glossary.md`,
which are moved by hand into the fork at step S0 (ADR 0013).

## Reference to chosen brainstorm / grilling

No separate `<slug>.brainstorm.md` was written; the grilling itself was the
brainstorm and is captured in ADRs 0009-0015 in `docs/ADR/`. This plan is the
output of the chosen direction.

## Goal and scope

Rewrite the Mosh application shell as a Flutter + Dart app over the retained
`mosh-core` Rust crate, working in a sandboxed fork at
`mossandmosh/mosh-flutter`. Slice one proves the bridge, the state stack, i18n,
and the core DM flow on desktop, behind a temporary fake gateway that is
removed before the slice closes.

### In scope (slice one)

- Fork repo at `mossandmosh/mosh-flutter`; ADRs 0009-0015 and glossary moved
  in by hand.
- `mosh-core::api` facade module + `crate-type` for six targets.
- `flutter_rust_bridge` integration and codegen; one smoke call (diagnostics).
- Riverpod v3 stack; `LocaleProvider`; `MaterialApp` with i18n delegates.
- `gen-l10n` with `app_en.arb` (template) and `app_ru.arb`, seeded from
  `src/features/private-dm/private-dm.content.ts` (~130 keys, 8 sections).
- Slice-one screens on the fake gateway: onboarding, invite paste,
  fingerprint confirm, one DM screen, diagnostics.
- Port `invite-uri.ts`, `invite-detection.ts`, `unread.ts`, `format.ts`,
  `private-dm.content.ts` to Dart (ADR 0012).
- Move `frame-crypto.ts`, `jitter-buffer.ts`, `call-drain.ts` into
  `mosh-core` (ADR 0012).
- Minimal CI: `cargo test`, codegen drift, `flutter test`, `gen-l10n` drift.
- Fork version line `0.8.0-dev`.

### Out of scope (later slices)

- Deep-link `mosh://` OS association (ADR 0015) - planned, not slice one.
- Mobile builds of the Moss Go shared library and mobile platform channels
  for secure storage (ADR 0011) - approached when mobile is targeted.
- `flutter integration_test` and cross-compilation for Android/iOS in CI.
- Voice call screens, org section, VPN consent, channels, private groups UI
  - the runtimes exist in `mosh-core` and are bound via `api`, but the Dart
  UI for them is later slices.
- Manual language switch UI (the `LocaleProvider` seam is laid in slice one).

## Implementation plan (ordered steps)

Each step lists its own done criteria and test steps inline, per `AGENTS.md`.

### S0 - Fork scaffolding

Create the fork as a separate Git repository and pull it locally into
`mossandmosh/mosh-flutter`. Do not branch inside `mosh`.

- Create remote fork repo (confirm URL with user first).
- `git clone` into `mossandmosh/mosh-flutter`.
- `flutter create mosh-flutter` (or rename root) with platform dirs for
  windows, macos, linux, android, ios.
- Add `mosh-core` as a path dependency or subtree so the fork builds it;
  keep the `moss/` submodule pin `v0.8.14` inherited from upstream.
- Move ADRs 0009-0015 and `docs/flutter-fork-glossary.md` from the current
  `mosh` tree into `mosh-flutter/docs/ADR/` and `mosh-flutter/docs/`. Do NOT
  commit them in the current `mosh` tree.
- Set `pubspec.yaml` version to `0.8.0-dev`; add `flutter_localizations`,
  `intl`, `flutter_rust_bridge`, `flutter_riverpod` (v3), `hooks_riverpod`.
- `.gitignore` Flutter + Rust build artifacts; add `mosh-core/target` and
  generated `AppLocalizations` policy (decided in S3).
- Create `docs/Architecture.md` in the fork with a Mermaid diagram matching
  ADR 0009 boundaries.

Done criteria:
- [ ] Fork repo cloned locally at `mossandmosh/mosh-flutter`.
- [ ] `flutter create` runs; `flutter -v` lists all six platform folders.
- [ ] ADRs and glossary present in fork `docs/`; not committed in `mosh`.
- [ ] `pubspec.yaml` has all required deps; version `0.8.0-dev`.
- [ ] `docs/Architecture.md` exists with a Mermaid diagram.

Test steps:
- `flutter doctor` clean on desktop.
- `git status` in upstream `mosh` shows no ADR/plan commits.

### S1 - mosh-core::api facade and crate-type

Add a thin `api` module in `mosh-core` that adapts the existing runtimes to the
Dart contract. Each current Tauri command maps to one `api` function; each
Tauri event maps to one `api` function returning `StreamSink<T>`. The `api`
module is the only Rust surface the bridge sees (ADR 0010).

- Set `mosh-core/Cargo.toml` `[lib] crate-type = ["lib","cdylib","staticlib"]`.
- Add `mosh-core/src/api/mod.rs` and per-runtime `api/*.rs` files
  (`api/diagnostics.rs`, `api/private_dm.rs`, `api/channel.rs`,
  `api/private_group.rs`, `api/org.rs`, `api/network.rs`, `api/vpn.rs`).
- Implement slice-one subset first: diagnostics, private_dm (create_invite,
  accept_invite, send_message, poll_session, list_sessions, close_session),
  and the session-snapshot event stream. Leave the rest as stubs that
  compile but `todo!()`.
- Use the existing runtime types verbatim; `api` only adapts signatures and
  injects platform-specific secure-storage backend selection.

Done criteria:
- [ ] `mosh-core/Cargo.toml` has the three crate-types.
- [ ] `api` module compiles; slice-one functions implemented, rest stubbed.
- [ ] Each implemented `api` function maps 1:1 to a Tauri command name.

Test steps:
- `cargo build -p mosh-core` on desktop.
- `cargo test -p mosh-core` (existing tests must stay green).
- New `api` unit tests for the slice-one functions.

### S2 - flutter_rust_bridge integration and smoke call

Generate Dart bindings from `mosh_core::api` and prove one round trip.

- Add `flutter_rust_bridge` config in `pubspec.yaml`:
  `rust_input: crate::api`, `rust_root: mosh-core/`, `dart_output: lib/src/rust`.
- Run `flutter_rust_bridge_codegen integrate`.
- Write a Rust `api::app_diagnostics()` returning a struct; generate the
  Dart binding; call it from a `main()` smoke screen and print the result.
- Set up desktop build hooks so `cargo` builds `mosh-core` `cdylib` for the
  host target and the app loads it.

Done criteria:
- [ ] `flutter_rust_bridge_codegen` runs clean.
- [ ] `flutter run -d windows` (or host) shows the diagnostics struct from
  Rust on screen.
- [ ] Generated bindings are committed (or generated in CI - decided S3/S7).

Test steps:
- Smoke widget test asserts the diagnostics struct is non-empty.
- `cargo test -p mosh-core` still green.

### S3 - Riverpod stack and i18n skeleton

Lay the state and localization foundations before any feature screen.

- `ProviderScope` at app root; `MaterialApp` with
  `localizationsDelegates: AppLocalizations.localizationsDelegates` plus
  `GlobalMaterialLocalizations`/`GlobalWidgetsLocalizations`, and
  `supportedLocales: [Locale('en'), Locale('ru')]`.
- `flutter: generate: true` in `pubspec.yaml`; `l10n.yaml` with
  `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`,
  `output-localization-file: app_localizations.dart`.
- Seed `lib/l10n/app_en.arb` from `private-dm.content.ts` (8 sections, ~130
  keys). Translate to `lib/l10n/app_ru.arb`.
- `LocaleProvider` (Riverpod) holding the active `Locale`; defaults to device
  resolution. No switch UI in slice one.
- Define the `Gateway` interface in Dart (the seam for the fake and the real
  bridge, ADR 0013): one method per slice-one `api` function, one `Stream`
  per slice-one event.

Done criteria:
- [ ] `flutter gen-l10n` produces `AppLocalizations`.
- [ ] `app_en.arb` and `app_ru.arb` cover all 8 sections from `private-dm.content.ts`.
- [ ] `MaterialApp` resolves `en`/`ru` from device locale.
- [ ] `Gateway` interface defined; no widget depends on a concrete gateway.

Test steps:
- Widget test: a dummy screen renders a localized string in `en` and `ru`.
- `flutter test` passes with `gen-l10n` output present.
- ARB key count matches the `private-dm.content.ts` entry count (~130).

### S4 - Fake gateway and slice-one screens

Implement the slice-one UI against the fake gateway so widget tests run
without the Rust runtime (ADR 0013). Fake is gated behind the `Gateway`
interface and a single provider.

- `FakeGateway implements Gateway` in Dart with canned snapshots and an
  in-memory session list. No crypto, no Rust.
- Riverpod providers for slice-one server state as `AsyncNotifier`s
  consuming `Gateway`: `diagnosticsProvider`, `sessionListProvider`,
  `sessionSnapshotProvider` (a `Stream` provider), `inviteFlowProvider`.
- Screens: onboarding (display name), invite paste (URI field + parse via
  ported `invite_uri.dart`), fingerprint confirm, one DM screen (message
  list + composer), diagnostics.
- Port `invite_uri.dart`, `invite_detection.dart` (clipboard via
  `Clipboard.getData`), `unread.dart`, `format.dart`, content strings to ARB.
- Ephemeral UI state (open drawer, selected session, composer draft) in
  `StatefulWidget` / `flutter_hooks`, never in providers (ADR 0010).
- Wire the fake as the default `Gateway` provider behind a debug flag.

Done criteria:
- [ ] All slice-one screens render in `en` and `ru`.
- [ ] Invite paste parses a `mosh://invite?...#fp=...` URI into the same
  contracts as `invite-uri.ts`.
- [ ] Fingerprint confirm gate blocks sending until confirmed.
- [ ] DM screen shows canned messages from `FakeGateway` and lets the user
  send a message that appears locally.
- [ ] Diagnostics screen shows the fake runtime status.
- [ ] No widget imports the real `flutter_rust_bridge` API directly.

Test steps:
- Widget tests per screen against `FakeGateway`, asserting user flows:
  onboarding -> invite paste -> fingerprint confirm -> send message.
- `invite_uri.dart` unit tests mirroring `invite-uri.test.ts` cases.
- `unread.dart` unit tests mirroring `unread.test.ts`.
- No mocks of the gateway; the fake IS the real test instance.

### S5 - Real bridge behind the same Gateway

Swap the fake for the real `flutter_rust_bridge` API without touching
widgets, then gate the fake out (ADR 0013 removal step).

- `RealBridgeGateway implements Gateway` wrapping the generated `api`.
- A provider switch (debug flag / build flavor) selects fake vs real.
- Run the slice-one screens against the real bridge on desktop; verify the
  diagnostics struct and a real (loopback) session snapshot stream.
- Remove the fake as the default; keep it flagged ONLY if an ADR-extended
  exception is recorded. Default path is removal before slice close.

Done criteria:
- [ ] `RealBridgeGateway` implements the full slice-one `Gateway`.
- [ ] Slice-one screens work on desktop with the real bridge.
- [ ] Fake gateway is removed OR kept behind an explicit flagged exception
  with an ADR note. No silent default fake.
- [ ] No widget changes between S4 and S5 (only the provider swap).

Test steps:
- Real-bridge integration test: start `mosh-core` runtime, create an invite,
  paste it in a second instance (loopback or two windows), confirm
  fingerprint, exchange one message. Asserts the real Rust path.
- `cargo test -p mosh-core` and `flutter test` both green.
- Coverage: changed Dart code reaches 80% line / 70% branch on the real
  path; critical flows (invite -> confirm -> send) at 90% line.

### S6 - Port crypto/transport into mosh-core (ADR 0012)

Move the three transport files out of the frontend contract into Rust so the
wire format has one source of truth. This is slice-one-adjacent: the voice
screens are out of scope, but the Rust-side ports unblock the next slice and
remove the duplicated crypto.

- `mosh-core/src/voice_call_frame_crypto.rs` from `frame-crypto.ts`
  (AES-GCM frame seal/open; reuse `aes-gcm 0.10`).
- `mosh-core/src/voice_call_jitter.rs` from `jitter-buffer.ts`.
- `mosh-core/src/voice_call_drain.rs` from `call-drain.ts` (drain loop as a
  runtime method).
- Port the corresponding TypeScript tests to `cargo test`.
- Do NOT add a Dart voice UI in this step.

Done criteria:
- [ ] Three new Rust modules compile and are unit-tested.
- [ ] `frame-crypto` Rust tests match the TS cases byte-for-byte where the
  wire format is shared.
- [ ] `jitter-buffer` Rust tests match the TS reorder/gap behavior.
- [ ] The TypeScript originals are marked for removal in the next slice
  (not deleted in slice one to avoid churn).

Test steps:
- `cargo test -p mosh-core --lib voice_call_`.
- Cross-check nonce/direction-bit behavior against `frame-crypto.test.ts`.

### S7 - Minimal CI

CI matrix per ADR 0015, slice-one scope only.

- Job 1: `cargo test -p mosh-core` on the desktop host.
- Job 2: regenerate `flutter_rust_bridge` bindings; fail if committed
  bindings drift from Rust signatures.
- Job 3: `flutter test` (unit + widget).
- Job 4: `flutter gen-l10n`; fail if generated `AppLocalizations` or ARB
  drift.
- Job 5 (close-out only): real-bridge integration test from S5.
- No mobile cross-build, no `integration_test` on devices in slice one.

Done criteria:
- [ ] All five jobs green on the fork's default branch.
- [ ] Drift jobs actually fail on a deliberate mismatch (verified once).
- [ ] CI runs on every PR and on main.

Test steps:
- Push a binding-drift commit; confirm Job 2 fails.
- Push an ARB-drift commit; confirm Job 4 fails.

### S8 - Documentation close-out

- Update `docs/Architecture.md` in the fork with the final slice-one Mermaid
  diagram (boundaries, bridge, providers, fake-gateway seam).
- Update `docs/flutter-fork-glossary.md` with any terms added during
  implementation.
- Add a `docs/Features/private-dm.md` with a Mermaid sequence for the
  invite -> confirm -> send flow under the bridge.
- Record the fake-gateway removal status (removed or flagged exception).

Done criteria:
- [ ] Architecture doc Mermaid renders.
- [ ] Feature doc Mermaid renders.
- [ ] Glossary has no undefined cross-references.

Test steps:
- Render Mermaid in the fork's doc preview; fix until it renders.

## Constraints and risks

- Bridge drift: Rust signatures and Dart bindings can desync. Mitigation:
  codegen-drift CI job (S7).
- Fake gateway becoming permanent: the slice-one removal gate (S5) and the
  flagged-exception rule (ADR 0013) prevent silent default fake.
- Moss pin inheritance: slice one uses upstream `v0.8.14` unchanged; any bump
  is deliberate and recorded, never a side effect.
- Mobile secure storage: not exercised in slice one; the `SecureSecretStore`
  trait seam (ADR 0011) means mobile is one backend implementation, not a
  rewrite.
- i18n key drift: ARB and generated `AppLocalizations` can desync;
  `gen-l10n`-drift CI job catches it.
- File/size limits from `AGENTS.md` (`file_max_loc: 400`, `type_max_loc:
  200`, `function_max_loc: 50`, `max_nesting_depth: 3`) apply to both Dart
  and Rust in the fork.

## Testing methodology

- TDD default: write the failing test first for each new behavior (Dart and
  Rust).
- Slice-one widget tests run against `FakeGateway` in the dev loop for
  speed; the real-bridge integration test runs in CI at close-out.
- No mocks/fakes of the gateway beyond the single `FakeGateway` test
  instance, which is the real test double (ADR 0013). The real path uses the
  real `mosh-core` through the bridge.
- `invite_uri.dart` and `unread.dart` unit tests mirror the existing TS
  tests case-for-case so behavior is preserved.
- Rust ported crypto tests (`frame-crypto`, `jitter-buffer`, `call-drain`)
  match the TS assertions byte-for-byte where the wire format is shared.
- Coverage: 80% line / 70% branch on changed Dart; 90% line on the
  invite -> confirm -> send critical flow. Repository coverage must not drop.
- Flaky tests are failures; fix the cause.

## Failing-tests baseline

Before starting implementation, establish the real baseline:

- [ ] In upstream `mosh`: `npm test` (typecheck + vitest + cargo test) - record
  the current pass/fail counts. Any pre-existing failures are added here as
  tracked items with symptom, suspected cause, and fix status.
- [ ] In the fork: there is no baseline yet at S0; the first `flutter test`
  run after S3 is the fork baseline.

(No failing tests are assumed; if the upstream baseline shows failures,
 they are listed here before any slice-one work begins.)

## Ordered final validation

Per `AGENTS.md`, ordered skills/commands with reason:

1. `cargo fmt --manifest-path mosh-core/Cargo.toml --check` - Rust formatting
   gate before tests.
2. `cargo test -p mosh-core` - core runtime and ported crypto tests.
3. `flutter_rust_bridge_codegen` (drift check) - bindings match Rust.
4. `flutter test` - Dart unit + widget tests on the fake path.
5. `flutter gen-l10n` (drift check) - ARB and `AppLocalizations` match.
6. Real-bridge integration test (S5) - the critical invite -> confirm -> send
   flow over the real Rust runtime.
7. `flutter analyze` - Dart lint gate.
8. Coverage report - assert 80/70 (90 on critical flow) and no drop.

## Checklist (done criteria per step)

- [ ] S0 fork scaffolded; ADRs moved; no commits in upstream `mosh`.
- [ ] S1 `api` facade + crate-type; slice-one functions implemented.
- [ ] S2 bridge smoke call works on desktop.
- [ ] S3 Riverpod + i18n skeleton; ARB ru/en seeded.
- [ ] S4 slice-one screens on fake gateway; ports done; tests green.
- [ ] S5 real bridge swapped in; fake removed/flagged; integration green.
- [ ] S6 crypto/transport ported to `mosh-core`; Rust tests green.
- [ ] S7 minimal CI green; drift jobs verified to fail.
- [ ] S8 docs closed out; Mermaid renders.
- [ ] Coverage bars met; repository coverage not dropped.

## Explicit future-slice reminders (do not lose)

- Deep-link `mosh://` OS association (ADR 0015) - slice two candidate.
- Mobile Moss builds + secure-storage platform channels (ADR 0011).
- Voice call, org, VPN, channels, private groups Dart UI - runtimes are
  already bound via `api`, UI is later slices.
- Manual language switch widget - `LocaleProvider` seam is laid in S3.
## Moss release pin

Inherited from upstream at fork time: `v0.8.14` (see `moss.config.json`).
Slice one does NOT bump the pin. Any future bump is a deliberate step with
its own ADR note.
---

## Follow-up slice (closing slice-one tails)

Slice 1 shipped (HEAD `7ae704b docs: close out slice one`). Five tails were
recorded in the close-out handoff; this slice closes them with atomic tasks.
One subagent = one task; the orchestrator makes the conventional commit.

- [ ] **FU-1: Make NativeRuntimeStatus sub-structs non-opaque.**
  - Root cause: `NativeRuntimeStatus` is `#[frb(non_opaque)]` but its 5 fields
    (`MossRuntimeStatus`, `SecureStorageStatus`, `PersistenceRuntimeStatus`,
    `OpenMlsSmokeStatus`, `OpenMlsRoundTripStatus`) stay auto-opaque, so Dart
    cannot read field values. `FakeGateway.nativeRuntimeStatus()` throws
    `UnsupportedError`; `DiagnosticsScreen` renders `<opaque: ...>`.
  - Rust: add `#[frb(non_opaque)]` to those 5 structs.
  - Convert `&'static str` fields to owned `String` (frb 2.12 quirk: non_opaque
    breaks on `&'static str`, as already done for `AppDiagnostics`). Update
    every constructor to `.to_string()` the consts.
  - Regen bindings: `cargo install flutter_rust_bridge_codegen --version 2.12.0
    --locked` then `flutter_rust_bridge_codegen generate --no-dart-fix
    --no-dart-format --no-deps-check --no-build-runner --no-rust-format`.
  - Update `FakeGateway.nativeRuntimeStatus()` to return real field data;
    collapse the `DiagnosticsScreen` split-path so native status goes through
    the `Gateway` seam (or keep split-path but make `_describe` read fields).
  - Verify: `cargo test --manifest-path mosh-core/Cargo.toml` green;
    `git diff --exit-code lib/src/rust mosh-core/src/frb_generated.rs` (no
    drift after regen); `flutter analyze` clean; `flutter test` 42/42; the
    diagnostics widget test asserts readable field values, not `<opaque>`.
- [ ] **FU-2: ARB key for DiagnosticsScreen AppBar title.**
  - Add `diagnosticsDiagnostics` to `lib/l10n/app_en.arb` (template) and
    `app_ru.arb`; replace the hardcoded `Text('Diagnostics')` in
    `diagnostics_screen.dart` with `AppLocalizations.of(context)`.
  - Clear the existing `TODO(slice-one)` comment.
  - Verify: `flutter test` green; `flutter gen-l10n` regen (gitignored output,
    but no ARB drift).
- [ ] **FU-3: Dedup invite_detection.dart.**
  - `invite_detection.dart` duplicates parse logic already in `invite_uri.dart`.
  - Consolidate so `invite_uri.dart` is the single source; `invite_detection`
    only adds the clipboard `Clipboard.getData` + timing concerns.
  - Verify: existing invite tests still pass.
- [ ] **FU-4 (optional): Restore clippy + mosh-probe to CI.**
  - Re-add the `clippy` job and the `mosh-probe` crate to `.github/workflows/ci.yml`
    if dropped scope is still cheap enough.
  - Verify: CI matrix green.

## Slice 2 (after follow-up): deep-link mosh:// desktop

Per ADR 0015. Windows registry association + launch-arg parsing in `main()`.
Mobile intent-filter / CFBundleURLSchemes deferred to the mobile slice. The
detailed step list is filled in when this slice starts.
