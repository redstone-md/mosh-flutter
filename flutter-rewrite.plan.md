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

- [x] **FU-1: Make NativeRuntimeStatus sub-structs non-opaque.** DONE — commit `063f7d8`. The 5 sub-structs are `#[frb(non_opaque)]` with owned `String` fields; the two `Result<OpenMlsXxxStatus,String>` fields became non-opaque `OpenMlsSmokeRuntimeStatus`/`OpenMlsRoundTripRuntimeStatus` wrappers (frb 2.12 auto-opaques `Result` fields). FakeGateway returns real data; DiagnosticsScreen renders real fields. cargo test 215/0, analyze clean, flutter test 43/43, fmt clean, codegen idempotent.
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
- [x] **FU-2: ARB key for DiagnosticsScreen AppBar title.** DONE — commit `1976db0`. `diagnosticsDiagnostics` added to en/ru ARB; hardcoded `Text('Diagnostics')` replaced with `AppLocalizations.of(context)!.diagnosticsDiagnostics`; TODO cleared. analyze clean, flutter test 43/43.
  - Add `diagnosticsDiagnostics` to `lib/l10n/app_en.arb` (template) and
    `app_ru.arb`; replace the hardcoded `Text('Diagnostics')` in
    `diagnostics_screen.dart` with `AppLocalizations.of(context)`.
  - Clear the existing `TODO(slice-one)` comment.
  - Verify: `flutter test` green; `flutter gen-l10n` regen (gitignored output,
    but no ARB drift).
- [x] **FU-3: Dedup invite_detection.dart.** DONE — commit `665afd4`. Removed the inlined second parse copy + private enum; detection now imports `invite_uri.dart` and re-exports `InviteParseErrorCode`/`InviteParseError` so the test's single import still resolves. `_tryParseDm`/`_tryParseGroup` are thin try/catch wrappers over the canonical parser. Org-bundle detection + family-branched fingerprint message kept. One boundary (`mosh:foo` → `invalidUrl` not `invalidScheme`) aligned to uri. analyze clean, flutter test 43/43, invite/ 18/18.
  - `invite_detection.dart` duplicates parse logic already in `invite_uri.dart`.
  - Consolidate so `invite_uri.dart` is the single source; `invite_detection`
    only adds the clipboard `Clipboard.getData` + timing concerns.
  - Verify: existing invite tests still pass.
- [ ] **FU-4 (deferred — not cheap): Restore clippy + mosh-probe to CI.**
  Investigated: FU-4 is NOT a cheap restoration.
  (a) `cargo clippy --manifest-path mosh-core/Cargo.toml --all-targets`
  exits 0 but emits 94 warnings, almost all `unused variable` on the
  `todo!()` stubs in `mosh-core/src/api/*.rs` (channel/group/org/network/vpn).
  A strict `-D warnings` gate would fail today; gating without `-D` is a
  weak no-op (clippy exit 0 even with warnings). Real value needs the stub
  params cleaned first (`#[allow(unused)]` per stub or drop the unused
  args), THEN `cargo clippy -- -D warnings` in CI.
  (b) `mosh-probe/` is a standalone cargo crate (separate Cargo.toml, not
  a mosh-core workspace member) — a headless TWO-ENDED reachability probe
  that dlopens moss.dll, runs live MLS handshakes + message delivery over
  the real moss network (listen/dial, up to 180s timeout, two processes).
  Running it in CI on windows-latest needs two-process orchestration + a
  stable network path; it is the opposite of a cheap unit gate and is
  exactly why slice one dropped it. Its real value is as a manual /
  nightly integration probe, not a per-PR gate.
  Deferred as explicit follow-ups, not weak half-measures:
  - FU-4a: clean stub `unused` warnings in `api/*.rs`, add
    `cargo clippy -- -D warnings` job to `.github/workflows/ci.yml`. DONE —
    commit `6b11c70`. `#![allow(unused_variables)]` on the 4 stub modules
    (channel/org/private_group/vpn); removed 2 dead imports in org.rs;
    `cargo clippy --all-targets -- -D warnings` exit 0; registered
    `frb_expand` cfg in `mosh-core/Cargo.toml [lints.rust]` (frb macros emit
    `#[cfg(frb_expand)]`; without it the strict gate fails on 16 pre-existing
    `unexpected_cfgs`); clippy step added to rust-core CI (after fmt, before
    test). cargo test 215/0/5-ignored, flutter analyze clean.
  - FU-4b: add a `mosh-probe` job (likely nightly, two-process, with a
    relay bootstrap) — separate infra task, not per-PR.

## Slice 2 (current): deep-link mosh:// desktop

Per ADR 0015: single scheme `mosh://` everywhere, desktop-first. Mobile
intent-filter / CFBundleURLSchemes deferred to the mobile slice.

GAP discovered at slice-2 start: the slice-one screens (`InvitePasteScreen`,
`DmScreen`, `DiagnosticsScreen`, `OnboardingScreen`) are NOT reachable from
the running app. `main.dart` ships `MoshHome`, a static smoke-screen with no
`Navigator`/router and no route to any real screen. Upstream Tauri mosh was a
single-view stepper app (no URL routing; invite flowed through component state),
so there is no existing router to port. Deep-link needs a router to open into.
So slice 2 first lays a minimal named-route shell, then wires deep-link into it.

The Windows runner (`windows/runner/main.cpp`) ALREADY pipes launch args via
`GetCommandLineArguments()` -> `project.set_dart_entrypoint_arguments(...)`,
so a `mosh://...` arg passed at launch reaches Dart as an entrypoint argument.
The OS association (registry) is the missing piece on the Windows side.

Ordered atomic tasks. One subagent = one task; orchestrator commits.

- [x] **S2-1: Minimal named-route shell so the slice-one screens are reachable.** DONE — commit `5be0817`. go_router 17.3.0 + route table (`/` onboarding, `/join`, `/diagnostics`, `/dm/:id`). MoshApp → `MaterialApp.router`. Join tile → `/join`; Group tile kept 1:1 (later-slice placeholder); Diagnostics as AppBar action (cable_outlined). widget_test updated. analyze clean, flutter test 43/43.
  - Replace `MoshHome` smoke-screen with a `Navigator` (or `GoRouter`) shell
    exposing named routes for the slice-one screens: onboarding, invite-paste,
    diagnostics, dm (with sessionId arg). Home = onboarding (matches the React
    app's entry flow). Keep `MoshApp`/`ProviderScope`/locale wiring intact.
  - Add a tile/list on the home screen to reach invite-paste + diagnostics (so
    the screens are human-reachable without a deep-link for now; mirrors the
    React `onboardTileJoin*` entries already in the ARB).
  - No new screens; reuse the four existing ones. `DmScreen` takes a
    `sessionId` (already does).
  - Verify: `flutter analyze` clean; `flutter test` green (existing widget
    tests pin `MoshApp` rendering the AppBar — update if the home changed);
    manual `flutter run -d windows` reaches invite-paste from a tile.
- [x] **S2-2: Windows registry association for the mosh:// scheme.** DONE — commit `9d30796`. `app_links 7.2.1` (dep, not yet imported) + `win32_registry 3.0.3`; `lib/src/deeplink/mosh_url_scheme_windows.dart` writes `HKCU\Software\Classes\mosh` (URL Protocol + `shell\open\command` = `"<exe>" "%1"`). Called from `main()` after `RustLib.init()`, gated `Platform.isWindows`, idempotent + never throws. `main.cpp` untouched (arg piping already works). flutter test 45/45 (+2 guard tests).
  - Register `mosh://` -> mosh.exe in the Windows registry at install/run time
    (HKCU or HKLM `Software\Classes\mosh\shell\open\command`). Bundle id
    `app.mosh.desktop` per ADR 0009. Use a post-install step or a small
    registration helper; do NOT require admin for a dev build (HKCU).
  - The open command launches `mosh.exe` with the URI as a launch arg, which
    the existing `main.cpp` arg piping already forwards to Dart.
  - Keep it desktop-Windows only for this task; a `.reg`-style or programmatic
    registration is fine. Document how to verify (open a `mosh://...` link from
    a browser/Run dialog -> mosh.exe starts with the arg).
  - Verify: registration present in registry; round-trip launches mosh.exe.
- [x] **S2-3: Dart-side deep-link intake + route to invite-paste.** DONE — commit `4af9a27`. Runner calls `SendAppLinkToInstance()` (single-instance handoff). `mosh_deep_link.dart` subscribes `AppLinks().uriLinkStream`, gates scheme `== 'mosh'`, `appRouter.go('/join', extra: uri)`; cold-start replay buffer + post-frame callback; navigation try/catch. `/join` reads `state.extra`→`InvitePasteScreen(initialInviteUri:)`; screen seeds `_controller`+`_detection`. main() starts intake after RustLib.init(). Tests +3 (warm, scheme gate, cold-start replay) → 48/48.
  - Read the launch arg (entrypoint argument) in `main()`; if it is a
    `mosh://...` URI, route the app to the invite-paste screen with the URI
    pre-filled (reuse `detectInvite`). Use `app_links` (desktop launch-arg
    path) or the raw entrypoint arg — pick whichever needs the least new
    surface and stays testable.
  - Single scheme `mosh://` (ADR 0009/0015); no per-fork variant.
  - The invite-paste screen must accept a pre-fill (extend its controller init
    or a constructor arg) WITHOUT breaking the existing widget test (which
    types the URI).
  - Verify: `flutter analyze` clean; `flutter test` green; a unit/widget test
    that feeds a `mosh://invite?...#fp=...` entrypoint arg asserts the app
    navigates to invite-paste with the field pre-filled.
- [x] **S2-4: Slice 2 docs close-out.** DONE — Architecture.md gains a Slice Two Status section (route shell + Windows registration + intake); ADR 0015 Status → Accepted with a slice-two-outcome note (registry approach, mobile deferred). This plan marks S2-1..S2-3 done.
  - Update `docs/Architecture.md` with the route shell + deep-link intake.
  - ADR note (or update 0015) recording the registry association approach and
    that mobile remains deferred.
  - Update this plan: mark S2-1..S2-3 done.
## Slice 3 (mobile): BLOCKED on environment — Android NDK not installed

Research brief captured by subagent (Heisenberg): see notes below. The
first atomic mobile task is to cross-compile the Moss Go c-shared library
to `libmoss.so` for `GOOS=android GOARCH=arm64` via the NDK clang, place
it in `android/app/src/main/jniLibs/arm64-v8a/`, and add an android
bare-name dlopen candidate in `mosh-core/src/moss_runtime.rs`
(`default_candidate_paths()` has no android arm today).

BLOCKER: `flutter doctor` reports "Unable to locate Android SDK";
`ANDROID_NDK_HOME`/`ANDROID_SDK_ROOT` are empty, no SDK/NDK in any standard
or custom location on C:\ or D:\, `sdkmanager` not on PATH. Go cross-compile
to android/arm64 (`CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC=<ndk clang>`)
requires the NDK, which needs an interactive Android Studio install /
`sdkmanager` license acceptance (~1+ GB, GUI or interactive license flow).
This cannot be resolved from the sandbox without user action.

State of the fork as of this slice:
- `moss/` is a git submodule pinned `v0.8.14`; `go.mod` toolchain
  `go1.25.9`; only `cmd/moss-ffi/main.go` uses cgo (stdlib headers only).
- mosh-core dlopens moss via `libloading`; `MOSS_LIBRARY_NAME` resolves to
  `libmoss.so` on android (name is right; path probing is desktop-only).
- cargokit builds the **mosh-core** Rust crate for android (arm64-v8a,
  minSdk 21); moss is a SEPARATE Go dylib cargokit has no hook for.
- `src-tauri/` legacy project is still physically present in the fork
  (ADR 0009 says remove from the Flutter track — out of scope for the
  moss-load task; the android prepare script must NOT reuse its output dir).

Unblocks when: Android NDK is installed and `ANDROID_NDK_HOME` set (or
`flutter config --android-sdk` + NDK side-by-side). Then the first
mobile task is executor-shaped and ready to spawn.

### M-1: code written, build NOT verified (commit `4deb369`)

The code half of the first mobile task. `scripts/moss-prepare-android.mjs`
(NDK resolution, CC derivation, `CGO_ENABLED=1 GOOS=android GOARCH=arm64`
go build, output to `android/app/src/main/jniLibs/arm64-v8a/libmoss.so`) and
an android bare-name dlopen candidate in `mosh-core/src/moss_runtime.rs`
(with a runs-everywhere unit test).

**BLOCKER RESOLVED** — Android SDK 34+36 + NDK 27.0.12077973 installed at
`D:\android-sdk` (commandline-tools, licenses accepted, platform-tools,
platforms android-34/36, build-tools 34/36, ndk 27). `flutter config
--android-sdk D:\android-sdk`. Env: `ANDROID_NDK_HOME=D:\android-sdk\ndk\
27.0.12077973`.

**M-1 FULLY VERIFIED** (commits `4deb369` + `6c02c66` fs/promises fix):
`node scripts/moss-prepare-android.mjs` exits 0; produces a 19 MB
`libmoss.so` (go1.25.9, GOOS=android GOARCH=arm64) at
`android/app/src/main/jniLibs/arm64-v8a/libmoss.so`; all 8 FFI symbols
present (Moss_Init/Start/Stop/Subscribe/Publish/SetCallback/SetKeyStore/
Free) via `go tool nm`. Windows: cargo test 216/0/5-ignored, clippy clean,
analyze clean.

**Follow-up flagged**: the link emits ld.lld warnings — the Windows/x86
`C:\Users\nevermore\local\libolm\lib\libolm.a` is cgo-linked into an
android/arm64 .so. The .so builds and exports the FFI symbols, proving
the moss FFI pipeline, but a clean android-arm64 libolm is needed before
a real device runtime can exercise MLS. Separate task.
### M-2: persistence + Moss identity wired into the live runtime (commit `3471864`)
The first REAL consumer of SecureSecretStore (ADR 0011). api/private_dm.rs
construct_runtime now: MossFfiRuntime::load_default -> Persistence::open(
temp/mosh/history.redb) -> set_moss_keystore(persistence) ->
moss.install_keystore() -> from_shared_node(..., Some(persistence)) ->
rehydrate(). Conversations survive restart; Moss transport identity persists
(loads, not mints). Fail-closed: PersistenceError -> PrivateDmRuntimeError::
Persistence (new variant), never silently None. DB = temp/mosh/history.redb
(AttachmentStore's temp fallback; real app_data_dir via ADR 0010 bridge later).
New test persistence_and_identity_survive_restart proves identity-equality
across a simulated restart + history round-trip against the live
OsSecureSecretStore (Windows Credential Manager); teardown cleans history-dek-v1
keychain entry + temp dir.
Latent bug fixed: moss_ffi::tests::keystore_callbacks_round_trip_identity
set_moss_keystore(MemStore)s but never clears the Rust global — harmless until
the new test installed the Go Moss_SetKeyStore callbacks, which read the stale
MemStore identity and collapsed all peer ids (Bob loaded Alice's id). Added
test-only MossFfiRuntime::uninstall_keystore() + clear_moss_keystore()
([cfg(test)]-gated) in the new test teardown; Moss_SetKeyStore(None,None) nils
the Go callbacks so loadIdentityBytes short-circuits. Production never
uninstalls.
Verified: cargo fmt --check clean; clippy --all-targets -- -D warnings clean;
cargo test 217/0/5-ignored (serial, +1); flutter analyze clean.
Mobile secure-storage platform channel (Flutter -> Android Keystore) is now the
correct NEXT mobile task — the runtime consumes SecureSecretStore on desktop,
so a device backend is no longer dead code. ADR 0011 open question (which
Flutter plugin for Keystore/Keychain) must be rechecked via Context7 first.
### M-3: Android Keystore DEK injection (commit `23af8f8`)
Context7 resolved ADR 0011's open question: flutter_secure_storage fits
(Android backend is KeyStore-direct AES-GCM; EncryptedSharedPreferences
deprecated/ignored; biometrics opt-in for a later UX slice). Architecture A1:
Dart owns load+mint, hands 32 raw bytes to Rust via new frb
`set_history_dek(Vec<u8>)`; Rust `construct_runtime` prefers the injected DEK
via promoted `Persistence::open_with_dek` (desktop `open` unchanged, no mobile
`SecureSecretStore` impl needed). Moss transport identity rides free under
the same DEK. `set_history_dek` is idempotent-once (OnceLock, reject re-inject).
mobile_dek.dart: write-before-inject on mint (so a crash never orphans the
DB), fail-closed on missing-key+DB-exists, fast-throw on corrupt-length,
AndroidOptions(storageNamespace: "app.mosh.mobile"), Platform.isAndroid-gated
in main() before runApp. flutter_secure_storage 10.3.1 (9.x conflicts with
win32_registry ^3.0.3 via win32 version); storageNamespace API present in 10.x.
frb Vec<u8> -> List<int>, named-param adapter handled. Codegen idempotent.
Tests: Rust open_with_dek round-trip (no keychain touch); Dart 4 fake-storage
branch tests. Device-only piece = the real Keystore read in initMobileDek.
Verified: cargo 218/0/5-ignored (+1 Rust), clippy -D warnings clean, flutter
test 52/52 (+4), analyze clean, codegen idempotent, fmt clean.
Remaining mobile work (deferred): iOS Keychain, biometric/user-presence UI,
libolm android-arm64 (clean build for MLS on device), app_data_dir via the
ADR 0010 bridge (currently temp/mosh fallback shared by Rust+Dart), mobile
deep-link registration (Dart intake seam already platform-agnostic).
Remaining mobile work (deferred): iOS Keychain, biometric/user-presence UI,
libolm android-arm64 (clean build for MLS on device), app_data_dir via the
ADR 0010 bridge (currently temp/mosh fallback shared by Rust+Dart), mobile
deep-link registration (Dart intake seam already platform-agnostic).
### M-4: mosh:// scheme registered on Android + iOS (commit `481eea0`)
The OS-side half of mobile deep-link (ADR 0015). Android: a second
intent-filter on MainActivity (VIEW + DEFAULT + BROWSABLE + scheme=mosh,
autoVerify=false, scheme-only so invite/group/org all route; MAIN/LAUNCHER
unchanged, singleTop kept). iOS: CFBundleURLTypes with CFBundleURLSchemes=
[mosh], CFBundleURLName=app.mosh (ADR 0009); scene manifest untouched
(app_links handles scene/legacy open-url). The Dart intake from S2-3 is
platform-agnostic and now routes on both platforms. Single scheme mosh://.
Verified: analyze clean, flutter test 52/52 (no Dart changed); device
verification = opening a mosh:// link launches mosh -> /join pre-filled.
Remaining mobile work (deferred): iOS Keychain backend for the DEK (mirror
of M-3's Android path via flutter_secure_storage iOS), biometric/user-
presence UI (ADR 0011 default-on, separate UX slice), libolm android-arm64
clean build (MLS on device; the M-1 .so links a Windows/x86 libolm today),
app_data_dir via the ADR 0010 bridge (replace the temp/mosh fallback shared
by Rust+Dart), and a real device integration pass (build apk, install,
open a mosh:// link, confirm Keystore DEK + history persist).
### M-5: app_data_dir bridge (commit `62e5b52`)
The encrypted redb history DB + attachments moved out of the temp/mosh
fallback into the platform's app-support dir via path_provider
getApplicationSupportDirectory (Context7-confirmed for an app-private
encrypted DB). Dart resolves the dir, injects it into Rust via new frb
set_app_data_dir(String) (OnceLock<PathBuf>, idempotent-once), and uses the
same path locally so mobile_dek._historyRedbPath() and construct_runtime
agree (no Dart/Rust path divergence). main() runs setAppDataDirBridge on ALL
platforms before initMobileDek / deep-link intake / runApp; the None arm keeps
the temp fallback for tests that don't inject. A pure resolve_data_dir helper
makes the path-selection unit-testable.
Verified: cargo 222/0/5-ignored (+4 Rust), flutter 54/54 (+2), clippy clean,
analyze clean, codegen idempotent. Note: existing temp history.redb is orphaned
on first launch after upgrade (DB moves to %APPDATA%/.../mosh/history.redb);
expected path migration.
Remaining mobile work (deferred): iOS Keychain backend for the DEK, biometric/
user-presence UI (ADR 0011), libolm android-arm64 clean build (MLS on device),
and a real device integration pass (build apk, install, open mosh://, confirm
Keystore DEK + history persist across restart in the app-support dir).
Remaining mobile work (deferred): iOS Keychain backend for the DEK, biometric/
user-presence UI (ADR 0011), libolm android-arm64 clean build (MLS on device),
and a real device integration pass (build apk, install, open mosh://, confirm
Keystore DEK + history persist across restart in the app-support dir).
### M-6 (cancelled — non-task): libolm android-arm64 clean build
Investigation (Mendel, read-only: go env / rg / go tool nm) proved libolm is
NOT a moss dependency: zero olm_* symbols in moss or veil/core Go source, no
#cgo directive adds -lolm, and the M-1 .so contains 0 olm_* symbols (the 87
loose "olm" matches are all andybalholm/brotli — pure-Go). moss crypto is
pure-Go Noise (flynn/noise + golang.org/x/crypto). The libolm linkage came
100% from a globally-set go env (GOENV file pins CGO_LDFLAGS/CGO_CFLAGS at a
Windows/x86 libolm, left over from an earlier setup). Real fix = commit
`4cf7d05`: moss-prepare-android.mjs points GOENV at a per-invocation empty
temp file so go reads NO stored cgo flags for the android build; ld.lld
warnings gone; .so is 19 MB, 8 FFI symbols, 0 olm_*. MLS-on-device was never
blocked by libolm. libolm cross-compile is dropped from the plan.
Remaining mobile work (deferred): iOS Keychain backend for the DEK, biometric/
user-presence UI (ADR 0011), and a real device integration pass (build apk,
install, open mosh://, confirm Keystore DEK + history persist across restart
in the app-support dir).
## Mobile slice — M-7: biometric/user-presence gating (DONE, commit b3b2f60)
ADR 0011 requires user presence (biometric/PIN) to be DEFAULT-ON for key
release on mobile, failing closed on an insecure device. M-3 injected the
DEK into the Android Keystore namespace `app.mosh.mobile` but with NO
biometric gating (deferred). M-7 closes that gap.
Implementation: the real Keystore storage switched from the plain
`AndroidOptions()` (RSA-OAEP key wrap, no biometric support) to
`AndroidOptions.biometric(enforceBiometrics: true,
biometricOrDeviceCredential, ...)` via a new `@visibleForTesting
buildDekAndroidOptions()` builder in `lib/src/platform/mobile_dek.dart`. The
biometric constructor selects the KeyStore-backed `AES_GCM_NoPadding`
key+storage ciphers — the only combination that supports
`setUserAuthenticationRequired` — and `flutter_secure_storage` self-prompts
BiometricPrompt, so no `local_auth` dependency is needed. The namespace is
preserved from M-3 (existing Keystore entries stay addressable).
Scope discipline: biometrics affect only the real storage wiring + the new
builder. `resolveHistoryDek` and the `MobileDekStorage` seam are unchanged —
user presence only gates the Keystore read/write, not the
loaded/minted/fail-closed decision branches. `AndroidManifest` gained
`USE_BIOMETIC`. A host test (`mobile_dek_biometric_options_test.dart`) pins
the 8 biometric-config fields via `toMap()` so a regression that drops
`enforceBiometrics`, swaps the cipher, or loses the namespace fails fast.
Verify (Peirce review, 11/11 PASS against locked flutter_secure_storage
10.3.1 source): `flutter analyze` 0 issues; `flutter test` 55/55 pass. Real
biometric prompt + cross-restart persistence are verified on-device in the
integration pass, not here.
Remaining mobile work (deferred): iOS Keychain backend for the DEK (mirror of
M-3+M-7 under iOS, needs macOS/Xcode), and a real device integration pass
(install emulator+AVD or use a real device, build apk, open mosh://, confirm
Keystore DEK + history persist across restart in app-support, confirm
biometric prompt).

## Diagnostics slice — DiagnosticsDrawer wiring (DONE, commit 94724be)

The DiagnosticsDrawer primitives (SummaryCard, RuntimeError, SessionDiagnostics
with all 3 groups — Conversation details / Moss network / Moss events,
NoActiveSession, MeshDiagnostics, EventLog, and the 8 helpers) were built across
commits b69bae0..f93f077 as standalone, unwired primitives. This atomic wires
them into the DM screen as a modal peer-status drawer, 1-в-1 with React's
`src/features/private-dm/DiagnosticsDrawer.tsx`.

Implementation: new `lib/src/features/dm/peer_status_drawer.dart` (`PeerStatusDrawer`)
mirrors the React shell — translucent backdrop (tap to close, the React
`role=presentation onClick`), right-aligned aside (max 384px, left divider
border, the `aside`), header (plug icon + "Peer status" + refresh-while-disabled
+ close), and a `SingleChildScrollView` body reusing SummaryCard -> optional
RuntimeError -> SessionDiagnostics-or-NoActiveSession. No primitives were
duplicated. `DmScreen` gained a `_showPeerStatus` bool, an AppBar action
(Icons.electrical_services, tooltip openPeerStatus — the Flutter equivalent of
React's titlebar plug button), and a Stack body whose last child is
`Positioned.fill(child: PeerStatusDrawer(...))` when open. The drawer reads
`session: async.value` / `error: async.hasError ? async.error.toString() : null`
from the existing `activeSessionProvider` watch; `refreshing` is hardcoded false
and `onRefresh` re-invalidates `activeSessionProvider` (the React `refresh(false)`
poll loop is a later slice).

DM-only: channel/group branches are deferred — those Snapshot contracts don't
exist in the fork yet, so they pass null and hit the idle/error fallback in the
existing `diagnosticsSummary(l, session, error)` seam. New ARB keys (en + ru):
peerStatusTitle, refreshStatus, closePeerStatus, openPeerStatus.

Verify (independent review, Meitner, 9/9 PASS + 1 deferred-a11y note):
`flutter analyze` 0 issues; `flutter test` 190/190 pass; dm_screen.dart 468
lines (< 500); ARB trailing LF preserved on both files; scope clean (4 files).
The one deferred item is drawer a11y — React uses `role=dialog aria-modal=true
aria-labelledby`; Flutter has a `Semantics(container: true, label)` but no
focus-trap/scopedRoute. That is the next atomic (RuntimeError liveRegion is the
same a11y follow-up batch).

Next atomic (recorded): a11y follow-up — RuntimeError `Semantics(liveRegion:
true)` (React `role="alert"`) + PeerStatusDrawer modal `scopedRoute`/focus-trap.
Then the larger atomics: attachment transfer actions (Dart+Rust +
download/cancel/open_attachment + frb codegen + RealBridge/Fake), the
channels/groups contract slice (port ChannelSnapshot/GroupSnapshot to Rust api +
frb before any channels/groups UI), and FingerprintBadge (needs Gateway
confirm-fingerprint method).

## Slices landed since (commits 94724be..9231a71, not all individually journaled)

Between the early diagnostics wiring above and the sender-meta atomic below, the
following slices shipped (HEAD progression): a11y (liveRegion + scopedRoute),
attachment seam + AttachmentCard (4-state machine), channels/groups read + write
seams (poll/list/send/leave/close), ChannelDiagnostics + GroupDiagnostics,
FingerprintBadge (local confirm Set), AGP 9 migration (apk builds), emulator +
device integration pass (biometric prompt + Keystore DEK persist verified),
sessions list combined rail (DMs + channels + groups with unread badges), and
ChannelScreen/GroupScreen route shells. PeerStatusDrawer branching (9231a71)
closed drawer parity: session→channel→group→NoActiveSession, wired into all
three screens. `session` made optional so one drawer serves all three.

## Channel/group screen polish — sender-meta + grouping (DONE, commit 815da01)

First of the surface-by-surface channel/group polish atomics (mirrors how DmScreen
was built up). Ports React `messageItems`/`shouldGroup` (src/features/private-dm/
MessageLists.tsx) to channels + groups.

Grouping (new `channel_message_row.dart` / `group_message_row.dart`):
key = `fromFingerprint` (not `fromDevice` -- multi-party), window = 5 min
(GROUP_WINDOW_MS), null sentAtMs breaks grouping, first message never grouped.
Only the first row of a group renders the sender meta; grouped rows use a
tighter vertical margin. Per-feature modules keep the helper + row local for
orthogonality (channel/group don't depend on the DM feature for core row logic).

Sender meta: new `MultiPartySenderMeta` in `dm_helpers.dart` (shared UI-primitives
home), parameterized on primitives (fromDevice/fromFingerprint/sentAtMs) so it
stays decoupled from the distinct ChannelMessage/GroupMessage types. Renders
fromDevice (bold) + monospace shorten(fingerprint, 6) + optional MLS badge +
timestamp. A `showMlsBadge` flag (default true) expresses the React difference:
group rows render the badge, channel rows don't (MessageLists.tsx 273-279 vs
378-383). Channel passes false, group uses the default.

Two parity fixes caught by review (Banach, FAIL then fixed): (1) channel rows
were rendering an MLS badge React omits — added the flag; (2) both rows gated
meta with `!own && !grouped`, suppressing own-row meta — React (and the DM port)
render meta on every non-grouped row including own, so changed to `if (!grouped)`.
Three regression widget tests pin both fixes (own-row meta renders; channel
omits MLS badge, group keeps it).

Verify: `flutter analyze` 0 issues; `flutter test` 211/211 pass; all 5 touched
files < 500 lines (dm_helpers 323, channel_message_row 141, group_message_row
147, channel test 327, group test 302); tree clean at 815da01.

## Channel/group ConversationTools — search+filter (DONE, commit 855d233)

Port the message search + filter row (React ConversationTools.tsx) to channels
and groups. DmScreen already had this; channel/group screens had no search/filter.

Generalized the existing DM `filterDmMessages` into a faithful generic instead of
duplicating per feature (React's `filterMessages<T extends SearchableMessage>` is
one generic reused by all three *ChatList components). `conversation_tools.dart`
now exposes `SearchableMessage` interface + generic `filterMessages<T>` + public
`messageSearchText`; `filterDmMessages` is a one-line typed wrapper (observable DM
behavior unchanged -- 8 existing DM unit tests stay green, no migration).
`filterChannelMessages`/`filterGroupMessages` are thin typed wrappers in their
`*_message_row.dart` modules, delegating to the generic via per-kind
`_ChannelSearchable`/`_GroupSearchable` (reading fromDevice/body/attachment, NOT
fromFingerprint -- React's messageSearchText has no per-kind fingerprint override).

Screens (channel_screen.dart / group_screen.dart): `_search`/`_filter`
widget-local state; `ConversationTools` rendered as first body Column child
(same position as DmScreen); filter-then-group order (filter on the raw list
BEFORE group*Messages, matching React's `filterMessages(...) -> messageItems
(visibleMessages, ...)` so the grouping window stays correct on the visible
set); `DmSearchEmpty` rendered when filtered-empty-but-raw-non-empty, with the
no-messages-at-all branch kept separate. ARB unchanged (chatSearchPlaceholder
etc. are generic chatText.* in React, reused).

Tests: +20 (9 pure-function + 1 widget per screen), including a regression that
asserts fromFingerprint is NOT searchable. 231/231 green, analyze clean, all
files < 500 lines. The shared trio (ConversationFilter/ConversationTools/
DmSearchEmpty) living in the DM folder while channel/group import it is the same
mild cross-feature-import the prior review accepted for MultiPartySenderMeta;
a future rename to ConversationSearchEmpty + relocation to features/shared/
conversation is a tidy refactor, not a defect.

## Channel/group AttachmentCard render (display-only) (DONE, commit b879a02)

Port the React ChannelMessageRow/GroupMessageRow AttachmentCard conditional
(MessageLists.tsx) into the Flutter channel/group rows. The card renders IN
ADDITION to the body text, below it, when `message.attachment != null` --
matching DmMessageRow and React's placement exactly.

Row changes (channel_message_row.dart / group_message_row.dart): ctor gains
attachmentView (AttachmentView?) + onAttachmentDownload/onAttachmentCancel/
onAttachmentOpen, typed to match attachment_card.dart (download/cancel:
`void Function(String)`, open: `void Function(AttachmentDescriptor)`). Renders
`AttachmentCard(descriptor: message.attachment!, view: attachmentView, own: own,
onDownload/onCancel/onOpen: ...)` under `Text(message.body)` when
`message.attachment != null`, mirroring DmMessageRow's structure + prop order.

Screen changes (channel_screen.dart / group_screen.dart): per-message
AttachmentView looked up from the snapshot's attachments list by attachmentId
via `_findChannelAttachmentView`/`_findGroupAttachmentView` (linear scan,
byte-identical to DmScreen's `_findAttachmentView` -- the React
`attachments.views.get(attachment_id)` Map.get idiom ported as a scan per the
existing DM convention). The three transfer callbacks are NO-OP STUBS with a
`TODO(channel-group-attachment-transfer)` comment -- render-only stage, same
as the DM port's display-only `b7660f8` which preceded its gateway transfer
seam `99bc9d9`. Wiring to a channel/group attachment-transfer Gateway seam is
a later atomic (needs Rust + frb codegen).

Scope discipline: Rust, frb-generated, and Gateway files untouched (verified by
review via Select-String scan for Gateway/frb/transfer symbols -- zero matches).
Only the 4 lib files + 2 new test files changed.

Tests: +4 widget tests (2 per screen): positive case seeds an offered attachment
+ matching AttachmentView and asserts the card's file name + the offered state
label render (proves the per-message lookup wires the view in); regression case
asserts the card still renders with no matching view (pins the null-fallback
path). 235/235 green, analyze clean, all files < 500 lines.

Next atomics (recorded): ConversationTools (search/filter for channels/groups,
fingerprint-based comparison, mirroring DmScreen's filterDmMessages); then
attachments in channel/group screens, public-channel notice banner (channels) +
encryption notice (groups), admin badge + member-count subtitle (groups),
copy-invite (groups), retry row.
See the three sections above (855d233, b879a02) for the ConversationTools +
AttachmentCard-render atomics that already closed those entries; the remaining
work is the notice banners, admin badge, copy-invite, retry row, and the
channel/group attachment-transfer Gateway seam (Rust + frb, deferred).
See the sections above (855d233, b879a02, 3f9ae22, e93cb5d, 9cc0a93) for the
ConversationTools, AttachmentCard-render, notice-banners, admin/member-subtitle,
and copy-invite atomics that already closed those entries; the remaining work
is the retry row, the channel/group attachment-transfer Gateway seam (Rust +
frb, deferred), and two recorded non-blocking follow-ups.

## Crypto notice banners (DONE, commit 3f9ae22)

Port the React GroupNotice / PublicNotice (ActiveChatPanes.tsx L420-445) wired
as the active-chat afterHeader into the Flutter channel/group screens. New
shared CryptoNoticeBanner(icon, title, body, accent) widget in a neutral
lib/src/features/shared/crypto_notice_banner.dart (channel/group-specific -- DMs
have no notice, so a neutral home is MORE correct than the prior
dm_helpers.dart pattern; sound structural improvement, not a divergence).
Banner at the TOP of each screen's body Column, ABOVE ConversationTools
(matching React's header -> afterHeader -> ConversationTools order; Flutter's
AppBar is the header). Channel: Icons.tag (lucide IconHash -> closest Material
hash glyph), channelNoticeTitle/Body, accent Color(0xFF6CB7E8) (React --info
#6cb7e8). Group: Icons.lock (lucide IconLock), groupNoticeTitle/Body, accent
Color(0xFFB7D84A) (React --moss #b7d84a) -- exact hex translations of React's
CSS vars; border/icon-bg alphas track React's crypto-banner-{public,group}
rules. Semantics(label: title, container: true, excludeSemantics: true) mirrors
React's aria-label={noticeTitle}. The 4 ARB keys were already pre-staged (en
values byte-for-byte = React's private-dm.content.ts strings). Group's
needs_rejoin + orgAddPrompt fragments are separate features and NOT ported
(TODO marks them deferred). Tests: +2 (assert exact en title+body render);
237/237 green, analyze clean, all files < 500.

## Admin badge + member-count subtitle (DONE, commit e93cb5d)

Port the React ActiveGroupChat header subtitle + admin-pill
(ActiveChatPanes.tsx L311-326) into the Flutter GroupScreen AppBar. Flutter
3.44 AppBar has NO subtitle: parameter (verified against the SDK source), so
the title is a two-line Column (title Text + subtitle Text styled bodySmall --
the idiomatic equivalent). _groupSubtitle = isAdmin ? "${groupAdminBadge} · " :
"" + (memberCount == BigInt.one ? membersCountSingular(n) : membersCount(n)) +
groupScreenMlsStateSuffix(state) -> e.g. "admin · 2 members · MLS Active"
(admin), "2 members · MLS Active" (non-admin), "admin · 1 member · MLS Active"
(1-member). Matches React's exact template; memberCount (BigInt) -> int via
.toInt() before the ARB placeholder call. Admin-pill (_AdminPill, FIRST in
actions, mirroring React beforeSearchActions): only if isAdmin; Tooltip +
Icons.workspace_premium size 14 (closest Material to lucide IconCrown;
consistent with the group rail which uses the same icon) + "admin" label; no
space when !isAdmin. 2 new ARB keys (en + ru): membersCountSingular
("{count} member" / "{count} участник") + groupScreenMlsStateSuffix
(" · MLS {state}"). Existing membersCount + groupAdminBadge reused. Copy-invite
deferred (TODO). Tests: +4 (admin pill+prefix, non-admin neither, singular,
plural); 241/241 green, analyze clean, group_screen.dart 446 lines.

NOTE (non-blocking): the Russian member-count plural is grammatically naive
("2 участников" instead of "2 участника"), inherited from the pre-existing
membersCount ru value (not introduced here). A future i18n-polish atomic
should convert membersCount/membersCountSingular to a single ICU MessageFormat
plural key with the three Russian forms (one/few/many) and drop the
memberCount == BigInt.one branch.

## Copy-invite button (DONE, commit 9cc0a93)

Port the React ActiveGroupChat beforeSearchActions copy-invite button
(ActiveChatPanes.tsx L327-337) into the Flutter GroupScreen AppBar actions,
immediately after the admin-pill. Copies group.invite_uri to the clipboard and
shows a check icon for 1600ms before reverting. State: bool _inviteCopied +
Timer? _inviteCopyTimer on _GroupScreenState (widget-local, ADR 0010).
_copyInvite: null guard -> await Clipboard.setData(ClipboardData(text: uri))
(the repo's existing idiom from chat_create_screen.dart, no external package)
-> mounted guard -> setState(true) -> cancel prior timer -> Timer(1600ms) to
revert, mounted-guarded; dispose() cancels the timer. IconButton after
admin-pill: Icon(_inviteCopied ? Icons.check : Icons.copy, size: 14), tooltip
switches groupCopyInviteDone/groupCopyInvite, onPressed. size 14 matches
React's button (the menu action uses 15 -- not ported). Existing ARB keys
reused. Documented simplification: React's useEffect([inviteUri]) reset is
omitted -- harmless because GroupScreen remounts per groupId (go_router builds
a fresh GroupScreen per /group/:groupId), so _inviteCopied resets on
cross-group navigation. Tests: +3 (invite present renders button; tap writes
exact URI via flutter/services channel interception idiom from
chat_create_screen_test, flips to check + "Invite copied", reverts after
pump(1600ms); invite null renders no button); test surface widened via
setSurfaceSize(1600x1200) so the 4-icon actions row fits. 244/244 green,
analyze clean.

NOTE (non-blocking, HIGH PRIORITY before the next group header atomic):
group_screen.dart is at 499 lines -- exactly 1 under the 500 ceiling. The next
group header work (retry row, etc.) WILL overflow it. A refactor extracting
_AdminPill + the subtitle builder + the copy-invite IconButton + _copyInvite
into a dedicated lib/src/features/group/group_screen_header.dart widget should
land as the NEXT atomic before any more group header UI is added, to restore
headroom.

## Recorded non-blocking follow-ups (for future atomics)

1. group_screen.dart 499-line ceiling: extract header widgets into
   group_screen_header.dart (HIGH PRIORITY -- blocks the retry-row atomic).
2. Russian member-count plural grammar (membersCount/membersCountSingular):
   convert to a single ICU MessageFormat plural key with one/few/many forms;
   drop the memberCount == BigInt.one branch.
3. channel/group attachment-transfer Gateway seam: Rust + frb codegen for
   download/cancel/open_attachment parameterized by conversation kind (currently
   no-op stubs in the channel/group screens, deferred from b879a02).
4. Device integration pass -- history.redb persist: needs a full create_invite
   UI flow on the emulator (displayName entry + invite creation) to create the
   DB, then verify it survives restart. Not blocking -- basic integration
   (apk + biometric + Keystore DEK + onboarding) is already verified.
