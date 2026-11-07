# Mosh

Desktop-first Flutter + Riverpod, Rust via flutter_rust_bridge, Moss + OpenMLS.

## Scope
- Read `docs/Architecture.md`, relevant ADRs and the nearest `AGENTS.md`.
- Flutter: `lib/`. Rust: `mosh-core/`. Native probes: `mosh-probe/`.
- Do not modify `moss/` sources or sibling repositories.
- Issues/specs: use the itsaplan MCP, project `MOSH`. Before tracker reads,
  publication, triage or status changes, read
  [tracker instructions](docs/agents/issue-tracker.md) and
  [triage labels](docs/agents/triage-labels.md).

## Work
- Reuse existing components and dependencies. Keep changes feature-local.
- For complex work, write a short plan with scope, risks and checks.
- Bug fixes start with a regression test. Test caller-visible behavior.
- Widget tests use `test/support/`. Native integration tests use real dependencies.
- Update relevant docs when behavior or architecture changes.
- Record lasting preferences briefly, without duplicates.
- Ask before changing public contracts, dependencies, schemas or deleting tracked code.
- Never commit secrets or build artifacts, force-push main, or merge for a maintainer.
- Use atomic Conventional Commits after verification.
- Commit authors are only ForeverInLaw or Rxflex. No AI authorship or `Co-Authored-By` trailers.
- Branch names follow Conventional Commits types: `<type>/<short-scope>`, e.g. `fix/call-window`.

## Product
- Desktop first, then Android, then iOS.
- Moss discovery is automatic. No manual host/port fields.
- Security indicators display real runtime values and states.

## Checks
- Flutter: `flutter analyze`; `flutter test`; `dart format lib test integration_test`.
- Rust: `cargo fmt --manifest-path mosh-core/Cargo.toml`; `cargo test --manifest-path mosh-core/Cargo.toml`.
- Lint: `cargo clippy --manifest-path mosh-core/Cargo.toml --all-targets -- -D warnings`.
- Prepare Moss before runtime tests: `node scripts/moss-prepare.mjs`.
- Rust API changes require `flutter_rust_bridge_codegen generate` and a binding drift check.
- Windows integration requires debug; Android builds require `--target-platform android-arm64`.
- Limits: 400 lines/file, 200/type, 50/function, nesting 3. Document exceptions.
- Changed code: ≥80% line coverage, ≥70% branch coverage where available.
- Run relevant checks yourself. Report changed files, simplifications and risks.

## Test value
- Test caller-visible contracts and distinct failure classes; preserve known
  regressions. For deletions, record the full test path and evidence; name the
  retained test when removing a duplicate.
- UI tests: use local widget fixtures for validation and feedback; retain real
  routes for navigation, route lifetime and absence of navigation after failure.
- Run `python3 scripts/test-policy.py` before committing test changes. CI rejects
  focused tests. New skips/todos need a local reason and tracking issue; new
  timeout/retry overrides and real sleeps need the same narrow exception.
- Prefer completion events and controlled clocks. Keep real timing-contract,
  network and platform gates explicit. Historical exceptions are frozen, not a
  budget for new ones; see [test policy](docs/testing.md) for syntax and scope.
