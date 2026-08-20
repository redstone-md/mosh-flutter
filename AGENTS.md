# AGENTS.md

Project: Mosh
Stack: Desktop-first Flutter application with Dart, a shared Rust core (mosh-core) exposed via flutter_rust_bridge, a Moss (Go) shared library dlopened by mosh-core, and OpenMLS-oriented private messaging architecture.

Follows [MCAF](https://mcaf.managed-code.com/)

---

## Purpose

This file defines how AI agents work in this solution.

- Root `AGENTS.md` holds the global workflow, shared commands, cross-cutting rules, and global skill catalog.
- In multi-project solutions, each project or module root MUST have its own local `AGENTS.md`.
- Local `AGENTS.md` files add project-specific entry points, boundaries, commands, risks, and applicable skills.

## Solution Topology

- Solution root: `mosh-flutter` (this repo).
- Rust core module: `mosh-core/` — the shared `cdylib` crate; its `api::` free functions are the single bridge surface.
- Moss core submodule: `moss/` — vendored Go checkout (https://github.com/redstone-md/moss). Source of the shared library; do not edit its source as part of Mosh tasks.
- `mosh-probe/` — headless probe crate used by `scripts/probe-e2e.mjs`.
- Projects or modules with local `AGENTS.md` files: none yet.
- Sibling directory `../mosh` (the original React/Tauri app, now historical) is outside this repository root. Do not modify it from Mosh tasks unless the user explicitly expands scope.
- The root `moss/` submodule is inside this repo; its generated artifacts land in ignored `moss-runtime/` (see native build chain below).

## Rule Precedence

1. Read the solution-root `AGENTS.md` first.
2. Read the nearest local `AGENTS.md` for the area you will edit.
3. Apply the stricter rule when both files speak to the same topic.
4. Local `AGENTS.md` files may refine or tighten root rules, but they must not silently weaken them.
5. If a local rule needs an exception, document it explicitly in the nearest local `AGENTS.md`, ADR, or feature doc.

## Conversations (Self-Learning)

Learn the user's stable habits, preferences, and corrections. Record durable rules here instead of relying on chat history.

Before doing any non-trivial task, evaluate the latest user message.
If it contains a durable rule, correction, preference, or workflow change, update `AGENTS.md` first.
If it is only task-local scope, do not turn it into a lasting rule.

Update this file when the user gives:

- a repeated correction
- a permanent requirement
- a lasting preference
- a workflow change
- a high-signal frustration that indicates a rule was missed

Extract rules aggressively when the user says things equivalent to:

- "never", "don't", "stop", "avoid"
- "always", "must", "make sure", "should"
- "remember", "keep in mind", "note that"
- "from now on", "going forward"
- "the workflow is", "we do it like this"

Preferences belong in `## Preferences`:

- positive preferences go under `Likes`
- negative preferences go under `Dislikes`
- comparisons should become explicit rules or preferences

Corrections should update an existing rule when possible instead of creating duplicates.

Treat these as strong signals and record them immediately:

- anger, swearing, sarcasm, or explicit frustration
- ALL CAPS, repeated punctuation, or "don't do this again"
- the same mistake happening twice
- the user manually undoing or rejecting a recurring pattern

Do not record:

- one-off instructions for the current task
- temporary exceptions
- requirements that are already captured elsewhere without change

Rule format:

- one instruction per bullet
- place it in the right section
- capture the why, not only the literal wording
- remove obsolete rules when a better one replaces them

## Native Build Chain

The Rust core dlopens the Moss shared library at runtime; it is never statically linked.

1. `node scripts/moss-prepare.mjs` builds the Go FFI (`go build -buildmode=c-shared` from `moss/`, GOTOOLCHAIN pin `go1.25.9`) into ignored `moss-runtime/moss.dll` (or `.so`/`.dylib`). This is the canonical candidate path.
2. `mosh-core/src/moss_runtime.rs::default_candidate_paths()` locates the library (current dir, `moss-runtime/`, `../moss-runtime/`, next to the exe). Do not reintroduce `src-tauri`-style paths from the dead React app.
3. CI (`codegen-drift`, `rust-core`, `integration-test`) runs `node scripts/moss-prepare.mjs` before cargo commands because adapter tests dlopen the library.
4. Android: `node scripts/moss-prepare-android.mjs` produces `android/app/src/main/jniLibs/arm64-v8a/libmoss.so` (ignored; regenerable).

Never check in, `git add`, or commit artifacts under `moss-runtime/` except `.gitkeep`. They are regenerable.

## Global Skills

List only the skills this solution actually uses.
Do not paste the whole framework catalog here.

- `mcaf-solution-governance` — use when defining or changing repo/project boundaries, local `AGENTS.md` policy, or governance rules.
- `mcaf-solid-maintainability` — use when designing/refactoring code structure, maintainability limits, and justified exceptions.
- `mcaf-feature-spec` — use for non-trivial feature specifications before implementation.
- `mcaf-architecture-overview` — use when creating or updating the architecture map.
- `mcaf-adr-writing` — use for durable architecture decisions such as crypto, native bridge, storage, and Moss release pinning.
- `mcaf-security-baseline` — use for security-sensitive work, especially E2EE, key storage, invite links, and native boundary design.
- `mcaf-testing` — use when planning or updating test coverage.
- `mcaf-ui-ux` — use for product UI work and design-system alignment.
- `mcaf-source-control` — use for branching, commit hygiene, and release/versioning policy.
- `mcaf-documentation` — use for user-facing or developer documentation.
- `mcaf-ci-cd` — use when adding build, packaging, or release automation.

## Rules to Follow (Mandatory)

### Commands

- Rust core, `build`: `cargo build --manifest-path mosh-core/Cargo.toml`
- Rust core, `test`: `cargo test --manifest-path mosh-core/Cargo.toml`
- Rust core, `format`: `cargo fmt --manifest-path mosh-core/Cargo.toml`
- Rust core, `lint`: `cargo clippy --manifest-path mosh-core/Cargo.toml --all-targets -- -D warnings`
- Flutter, `pub get`: `flutter pub get`
- Flutter, `analyze`: `flutter analyze`
- Flutter, `test`: `flutter test` (widget/unit; tests override `gatewayProvider` with `ScriptableGateway` from `test/support/`)
- Flutter, `format`: `dart format lib test integration_test`
- Flutter, `gen-l10n`: `flutter gen-l10n` (generated `lib/l10n/app_localizations*.dart` are gitignored)
- Bindings, `codegen`: `flutter_rust_bridge_codegen generate` (kept drift-free in CI; regenerate and commit when the Rust `api` surface changes)
- Full native dependency prep: `node scripts/moss-prepare.mjs` before any `cargo test`/`flutter build windows --debug` run that touches Moss.
- Windows app, `build`: `flutter build windows --debug` -> `build/windows/x64/runner/Debug/mosh.exe` (auto-deploys `mosh_core.dll`; `moss.dll` is dlopened from `moss-runtime/`). Debug is what `flutter test -d windows` drives — a release build strips the VM service the integration test needs.
- Windows installer, `package`: `flutter build windows --release` then `iscc /DAppVersion=<version> windows\installer\mosh.iss` -> `build/installer/mosh-<version>-setup.exe`. This is the only shippable artifact: `flutter build windows` emits a folder bundle, and `mosh.exe` alone cannot run without the DLLs beside it. Locally built installers are unsigned (see `CODE_SIGNING.md`).
- Android prep: `node scripts/moss-prepare-android.mjs` with `ANDROID_NDK_HOME` set -> `android/app/src/main/jniLibs/arm64-v8a/libmoss.so`.
- Android app, `build`: `flutter build apk --debug --target-platform android-arm64` -> `build/app/outputs/flutter-apk/app-debug.apk`. The `--target-platform` flag is REQUIRED: `jniLibs` carries only an arm64-v8a `libmoss.so`, so a default all-ABI build emits slices whose `dlopen` fails at runtime with no build-time error.

### Project AGENTS Policy

- Multi-project solutions MUST keep one root `AGENTS.md` plus one local `AGENTS.md` in each project or module root.
- Each local `AGENTS.md` MUST document:
  - project purpose
  - entry points
  - boundaries
  - module-local commands
  - applicable skills
  - local risks or protected areas
- If a module grows enough that the root file becomes vague, add or tighten the local `AGENTS.md` before continuing implementation.

### Maintainability Limits

These limits are repo-configured policy values. They live here so the solution can tune them over time.

- `file_max_loc`: `400`
- `type_max_loc`: `200`
- `function_max_loc`: `50`
- `max_nesting_depth`: `3`
- `exception_policy`: `Document any justified exception in the nearest ADR, feature doc, or local AGENTS.md with the reason, scope, and removal/refactor plan.`

Local `AGENTS.md` files may tighten these values, but they must not loosen them without an explicit root-level exception.

### Task Delivery

- Start from `docs/Architecture.md` and the nearest local `AGENTS.md`.
- Treat `docs/Architecture.md` as the architecture map for every non-trivial task.
- If the overview is missing, stale, or diagram-free, update it before implementation.
- Use vertical slices as the default architecture rule.
- Keep each feature in its own folder tree with its code, tests, contracts, docs, and supporting artifacts together.
- Prefer the smallest relevant feature slice over repo-wide scanning so context stays narrow.
- Define scope before coding:
  - in scope
  - out of scope
- Keep context tight. Do not read the whole repo if the architecture map and local docs are enough.
- If the task matches a skill, use the skill instead of improvising.
- Analyze first:
  - current state
  - required change
  - constraints and risks
- Before starting a brainstorm, decide whether the task is actually non-trivial.
- For non-trivial work, create a root-level `<slug>.brainstorm.md` file before making code or doc changes.
- For simple, short, or obvious work, skip the brainstorm and go directly to execution.
- Use `<slug>.brainstorm.md` to capture the problem framing, options, trade-offs, risks, open questions, and the recommended direction.
- Think through the task in the brainstorm before committing to implementation details.
- After the brainstorm direction is chosen, create a root-level `<slug>.plan.md` file.
- Keep the `<slug>.plan.md` file as the working plan for the task until completion.
- The plan file MUST contain:
  - a link or reference to the chosen brainstorm
  - task goal and scope
  - a detailed implementation plan with detailed ordered steps
  - constraints and risks
  - explicit test steps as part of the ordered plan, not as a later add-on
  - the test and verification strategy for each planned step
  - the testing methodology for the task: what flows will be tested, how they will be tested, and what quality bar the tests must meet
  - an explicit full-test baseline step after the plan is prepared
  - a tracked list of already failing tests, with one checklist item per failing test
  - root-cause notes and intended fix path for each failing test that must be addressed
  - a checklist with explicit done criteria for each step
  - ordered final validation skills and commands, with reason for each
- Use the Ralph Loop for every non-trivial task:
  - brainstorm in `<slug>.brainstorm.md` before coding or document edits
  - think through options and choose the intended direction before planning
  - turn the chosen direction into a detailed `<slug>.plan.md`
  - include test creation, test updates, and verification work in the ordered steps from the start
  - once the initial plan is ready, run the full relevant test suite to establish the real baseline
  - if tests are already failing, add each failing test back into `<slug>.plan.md` as a tracked item with its failure symptom, suspected cause, and fix status
  - work through failing tests one by one: reproduce, find the root cause, apply the fix, rerun, and update the plan file
  - include ordered final validation skills in the plan file, with reason for each skill
  - require each selected skill to produce a concrete action, artifact, or verification outcome
  - execute one planned step at a time
  - mark checklist items in `<slug>.plan.md` as work progresses
  - review findings, apply fixes, and rerun relevant verification
  - update the plan file and repeat until done criteria are met or an explicit exception is documented
- Implement code and tests together.
- Run verification in layers:
  - changed tests
  - related suite
  - broader required regressions
- If `build` is separate from `test`, run `build` before `test`.
- After tests pass, run `format`, then the final required verification commands.
- Run every repo-defined quality gate that is available for the stack and change scope (analyze, lint, complexity, coverage, codegen drift).
- The task is complete only when every planned checklist item is done and all relevant tests are green.
- Summarize the change, risks, and verification before marking the task complete.

### Documentation

- All durable docs live in `docs/` (or `.wiki/` if the repo already uses it).
- `docs/Architecture.md` is the required global map and the first stop for agents.
- `docs/Architecture.md` MUST contain Mermaid diagrams for:
  - system or module boundaries
  - interfaces or contracts between boundaries
  - key classes or types for the changed area
- Keep one canonical source for each important fact. Link instead of duplicating.
- Public bootstrap templates are limited to root-level agent files. Authoring scaffolds live in skills.
- Update feature docs when behaviour changes.
- Update ADRs when architecture, boundaries, or standards change.
- For non-trivial work, the plan file, feature doc, or ADR MUST document the testing methodology:
  - what flows are covered
  - how they are tested
  - which commands prove them
  - what quality and coverage requirements must hold
- Every feature doc under `docs/Features/` MUST contain at least one Mermaid diagram for the main behaviour or flow.
- Every ADR under `docs/ADR/` MUST contain at least one Mermaid diagram for the decision, boundaries, or interactions.
- Mermaid diagrams are mandatory in architecture docs, feature docs, and ADRs.
- Mermaid diagrams must render. Simplify them until they do.

### Testing

- TDD is the default for new behaviour and bug fixes: write the failing test first, make it pass, then refactor.
- Bug fixes start with a failing regression test that reproduces the issue.
- Every behaviour change needs new or updated automated tests with meaningful assertions.
- Tests must prove the real user flow or caller-visible system flow, not only internal implementation details.
- Tests should be as realistic as possible and exercise the system through real flows, contracts, and dependencies.
- Tests must cover positive flows, negative flows, edge cases, and unexpected paths from multiple relevant angles when the behaviour can fail in different ways.
- Prefer integration/API/UI tests over isolated unit tests when behaviour crosses boundaries.
- Integration tests are the default primary proof for feature-slice behaviour that spans multiple components.
- Do not use mocks, fakes, stubs, or service doubles in verification.
- Exercise internal and external dependencies through real containers, test instances, or sandbox environments that match the real contract.
- Flaky tests are failures. Fix the cause.
- Changed production code MUST reach at least 80% line coverage, and at least 70% branch coverage where branch coverage is available.
- The task is not done until the full relevant test suite is green, not only the newly added tests.

### Code and Design

- Everything in this solution MUST follow SOLID by default.
- Every class, object, module, and service MUST have a clear single responsibility and explicit boundaries.
- SRP and strong cohesion are mandatory for files, types, and functions.
- Vertical-slice architecture is mandatory unless a local rule or ADR documents an exception.
- Prefer composition over inheritance unless inheritance is explicitly justified.
- Large files, types, functions, and deep nesting are design smells. Split them or document a justified exception under `exception_policy`.
- Prefer named constants, enums, configuration, or dedicated value objects over magic literals. String literals are forbidden in implementation code.
- Design boundaries so real behaviour can be tested through public interfaces.
- The Rust `api::` signature surface is a public contract with the Dart side: changes require a cross-FFI review, codegen rerun + commit, and drift gate revalidation.

### Critical

- Never commit secrets, keys, or connection strings.
- Never skip tests to make a branch green.
- Never weaken a test or analyzer without explicit justification.
- Never introduce mocks, fakes, stubs, or service doubles to hide real behaviour in tests or local flows.
- Never introduce a non-SOLID design unless the exception is explicitly documented.
- Never spread one feature across unrelated folders when a vertical slice can keep it isolated.
- Never force-push to `main`.
- Never approve or merge on behalf of a human maintainer.

### Boundaries

ALWAYS:

- Read root and local `AGENTS.md` files before editing code.
- Read the relevant docs before changing behaviour or architecture.
- Run the required verification commands yourself.

Ask first:

- changing public API contracts
- adding new dependencies
- modifying database schema
- deleting tracked files or code
- committing build artifacts (never `git add` via `moss-runtime/`)

## Preferences

### Likes

- The product name is Mosh. Do not use Quiver/Quier naming.
- Build the desktop app first, then Android, then iOS.
- Prefer an actual Flutter app with the smallest needed screens over building a full design-system library first.

### Dislikes

- Do not treat `../quiver` or `../quiver-design` as the Mosh product source.
- Do not rewrite the dead React/Tauri app (`src/`, `src-tauri/`, npm build chain) except to remove it.
- Do not expose manual peer `host:port` or local listen-port fields; Moss discovery must use default/public trackers automatically.