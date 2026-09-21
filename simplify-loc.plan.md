# Plan — Repo-wide simplification, 30%+ LOC drop

Reference: `simplify-loc.brainstorm.md` (chosen: stacked PR series, concern-per-PR)

## Goal & scope

Drop ≥30% of handwritten LOC with zero behavior change. In scope: `lib/`
(excl. `lib/l10n/`), `test/`, `mosh-core/src` (excl. `frb_generated.rs`),
`mosh-probe/src`. Out of scope: generated bridge files (`frb_generated.*`),
`moss/` submodule, platform runner scaffolds (`windows/`, `macos/`, …).

## Baseline (measured 2026-09-21)

| area | LOC |
|---|---|
| Dart lib (handwritten) | 27,261 |
| Dart tests | 21,720 |
| Rust mosh-core (handwritten) | 28,103 |
| Rust mosh-core tests | 3,750 |
| mosh-probe | 1,429 |
| **total** | **82,263** |

Gates: `flutter analyze` clean ✅ · `flutter test` 838 passed, 0 failed ✅ ·
`cargo test` running (baseline below) · `cargo clippy -D warnings` per PR ·
`cargo fmt --check` per PR · codegen drift gate untouched (no api:: signature
changes allowed).

## PR series (each branch stacked on the previous)

- PR 1 `chore(simplify): strip dead-app port archaeology from comments` — `simplify/comments` ✅ committed b229187
- PR 2 `refactor(core): unify typing + session lookup across conversation kinds` — `simplify/core-unify` ✅ committed 5dde5fe
- PR 3 `refactor(core): split runtime god files into policy-sized modules` — `simplify/core-split` (in flight)
- PR 4 `refactor(ui): consolidate Flutter features and kill if-chains` — `simplify/ui-simplify`
- PR 5 `test: consolidate scaffolding` — `simplify/test-consolidate`
- PR 6 `docs: architecture truth pass + module map` — `simplify/docs`

### PR 1 `chore(simplify): strip port-archaeology comments` — `simplify/comments`
Steps:
1. Strip React/Tauri/1-в-1/CSS/aria archaeology from `lib/src` doc comments;
   keep the one-line purpose + any load-bearing why (crypto constants,
   paired timeouts cross-file).
2. Same treatment for `test/` headers.
3. Trim Rust `//` narrative comments that restate the next line; keep `///`
   docs that carry contracts.
4. Verify: `flutter analyze`, `flutter test`, `cargo fmt --check`,
   `cargo clippy -D warnings`, `cargo test`.
Done when: no `React|Tauri|1-в-1|aria-|className` mentions in lib comments;
all gates green.

### PR 2 `refactor(core): unify conversation-kind runtime machinery` — `simplify/core-unify`
Steps:
1. Move typing constants + expiry/refresh logic + event pushes into
   `conversation/typing.rs` shared by DM + group.
2. Move read-event helper + READ_HISTORY pruning into shared module.
3. Unify attachment facade quartet (send/download/cancel/stream_range)
   behind a `ConversationSession` extension in `conversation/attachments.rs`.
4. Unify session-map plumbing (drain_inbound/route_frame/tick/persist_tail)
   where the three runtimes already share `ConversationRuntime`.
5. Test-first: each unification lands with the existing suite green; no new
   mocks. Verify per step: `cargo test`, `cargo clippy`, `cargo fmt`.
Done when: no duplicated typing/attachment/outbox logic across the three
runtimes; god files measurably shrunk; all Rust tests green.

### PR 3 `refactor(core): split runtime god files into policy-sized modules` — `simplify/core-split`
Steps:
1. Split `private_dm_runtime.rs` into a directory: `state.rs` (session
   struct/restore/persist), `handshake.rs`, `calls.rs`, `control.rs`,
   `data.rs`, `pumps.rs`, `snapshots.rs` — each ≤400 LOC.
2. Split `private_group_runtime.rs` likewise: `org_gate.rs` (roster/admin),
   `commits.rs`, `resync.rs`, `sessions.rs`.
3. Split `channel_runtime.rs` if still >400 after unification.
4. Verify: full `cargo test` after each file move (pure moves, no logic).
Done when: no non-generated Rust file >400 LOC (tests exempted per policy
scope — checked separately); all tests green.

### PR 4 `refactor(ui): consolidate Flutter features and kill if-chains` — `simplify/ui-simplify`
Steps:
1. Split `media_viewer.dart` (730) and `attachment_card.dart` (492) into
   ≤400-LOC part files or sub-classes.
2. Merge duplicated header/menu/branch patterns (channel/group/dm headers
   share one data-driven header builder).
3. Replace if-if-if chains with map/switch dispatch in
   conversation_controller, media_stream_server, voice_composer.
4. Unify one-off helpers into `lib/src/util/` where ≥2 features share them.
5. Verify per file: targeted `flutter test test/features/...`, then full
   `flutter analyze` + `flutter test`.
Done when: no Dart lib file >400 LOC; analyze+tests green.

### PR 5 `test: consolidate scaffolding` — `simplify/test-consolidate`
Steps:
1. Extract repeated pump/settle/gateway-seed blocks into `test/support/`.
2. Delete per-file copies of identical setup; keep every assertion.
3. Verify: full `flutter test`; count of passed tests ≥ baseline.
Done when: test LOC down, pass count ≥838, analyze green.

### PR 6 `docs: architecture truth pass + module map` — `simplify/docs`
Steps:
1. Fix stale Architecture.md claims (api stubs) + add module map for new
   runtime layout; every new doc section gets a Mermaid diagram.
2. CHANGELOG entry per release notes convention.
3. Verify: manual read + `flutter analyze` (l10n untouched).
Done when: docs match the code; ADR updated if boundaries moved.

## Risks & tracked-failing-tests protocol

Full-suite baseline taken before any edit. Any test that fails after a step
gets one checklist item here with symptom + root cause + fix status, and is
fixed before the next step (no skipping, no weakening).

- [x] cargo test baseline: 366 passed, 0 failed, 6 ignored (258s)
- [x] flutter test baseline: 838 passed, 0 failed (~58s)
- [x] flutter analyze baseline: clean

## Final validation order (with reason)

1. `cargo fmt --check` — formatting gate
2. `cargo clippy --all-targets -D warnings` — lint gate
3. `cargo test --manifest-path mosh-core/Cargo.toml` — Rust behavior
4. `flutter analyze` — Dart static gate
5. `flutter test` — Dart behavior (must stay ≥838 passing)
6. `git diff --exit-code lib/src/rust mosh-core/src/frb_generated.rs` on
   main-vs-branch — proves no bridge drift
7. LOC accounting vs 82,263 baseline — proves ≥30%
