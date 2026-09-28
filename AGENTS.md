# Mosh

Desktop-first Flutter + Riverpod, Rust via flutter_rust_bridge, Moss + OpenMLS.

## Scope
- Read `docs/Architecture.md`, relevant ADRs and the nearest `AGENTS.md`.
- Flutter: `lib/`. Rust: `mosh-core/`. Native probes: `mosh-probe/`.
- Do not modify `moss/` sources or sibling repositories.

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
