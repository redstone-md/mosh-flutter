# Repository simplification

Scope: Flutter UI and state, Rust runtime and storage, native probes, build
tooling and architecture documentation. Preserve product behavior, bridge
contracts, persistence schemas, dependency versions and cryptographic checks.
Do not modify Moss.

The baseline is commit `6195121`. The reproducible tracked-source count includes
local `.patch` files and platform build scripts: 223,340 lines total; application
and tooling 70,866; dependency source and patches 83,795; generated bindings
23,509; tests 45,170. All tracked UTF-8 text, including docs and manifests,
contains 262,151 lines.
`python3 scripts/source-metrics.py 6195121 HEAD` measures Git blobs at each ref.
It prints the complete extension list and counts blank lines and comments.
Report dependency source separately from authored code. Report first-party
source and tests together as well, because moving inline Rust tests into named
test modules changes category totals without removing source.

Work proceeds in independently verified commits:

1. Replace the complete OpenMLS mirror with a pinned archive and complete local
   patch. Verify byte-identical source reconstruction and offline preparation.
2. Consolidate Rust runtime ownership and encrypted persistence operations.
   Split lifecycle, actions, transport callbacks and tests into named modules.
3. Unify repeated Flutter rendering and interaction helpers. Remove obsolete
   implementation histories while retaining invariants and useful comments.
4. Split the probe and cryptographic adapter by responsibility, shorten the
   architecture map and record how the final modules connect.
5. Run formatting, analyzers, strict Clippy, full Flutter and real-native Rust
   tests, bridge drift checks and focused coverage. Rebase on current main and
   open a ready PR with actual LOC counts and limitations.

Risks: durable write ordering, MLS admission and recovery, FFI callback lifetimes,
Flutter asynchronous lifetime guards and native source preparation. Existing
behavior tests remain. Code reduction does not justify removing security checks,
features or useful regression coverage. The vendor source migration adds a first
checkout preparation requirement; CI and Flutter native builds own it.

## Result

One PR groups atomic build, persistence, transport, runtime, MLS, probe, Flutter
and documentation commits. The code remains behind its existing bridge and
storage contracts. Dependency versions and schemas are unchanged.

| Scope | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| All tracked source, including local patches | 223,340 | 142,682 | 36.11% |
| Dependency source and patches | 83,795 | 6,127 | 92.69% |
| Application and tooling | 70,866 | 65,544 | 7.51% |
| Tests | 45,170 | 47,509 | +2,339 lines |
| First-party source and tests together | 116,036 | 113,053 | 2.57% |
| Generated bridge | 23,509 | 23,502 | 7 comment lines |
| All tracked UTF-8 text, including docs/manifests | 262,151 | 176,206 | 32.78% |

The overall reduction exceeds 30%. Most of it replaces an upstream mirror with
reproducible preparation; it does not shrink OpenMLS at runtime. The authored
reduction is smaller. Comment cleanup also contributes: Flutter production
physical lines dropped about 9%, while executable nonblank/comment lines
dropped about 2.5%. No feature, test case or cryptographic check was removed to
reach the target. Inline Rust tests moved into named files, explaining why the
separate application and test categories should not be interpreted in isolation.

Largest runtime roots: DM 1,072 → 372; group 1,045 → 363; channel 468 → 342;
organization 963 → 341; MLS adapter 871 → 91; probe main 1,429 → 50.
All authored application and test files fit 400 lines. Retained type/function
exceptions are [listed explicitly](simplification-size-exceptions.md).

Simplifications:

- One runtime-owner initializer caches each domain's success/failure and
  preserves independent locks. Named protocol handlers replace large receive
  branches; shared group construction, payload encryption and attachment decoding
  replace repeated setup and encoding.
- One encrypted database operation layer and kind-based history/record handling
  preserve transaction boundaries. Attachment request scheduling separates
  priority, timed retry gaps and sequential requests.
- Native symbols, callbacks, stream handling and node operations have separate
  modules. MLS setup, membership, commits, messages and snapshot storage share
  one adapter and typed codec errors.
- Flutter uses shared call cards, native focus traversal, modal Escape handling,
  MIME classification and header bundles. Theme recipes and scripted bridge
  facets have named responsibilities. Unused opening policies and security
  getters are removed; diagnostics still assert real runtime values.
- Architecture documentation becomes a current module/flow map, with ADRs
  retaining the decision history.

## Verification

- Flutter analysis and formatting pass; the final full suite passes 1,311 tests
  with five existing skips. Held/modified Escape regression cases failed before
  the fix and pass after it.
- Core build, formatting, strict all-target Clippy and full real-Moss Cargo tests
  pass: 497 top-level tests and 21 existing ignores, plus subprocess workers.
  The same complete suite passes under LLVM coverage. Probe unit tests pass
  (three cases) and strict all-target Clippy passes.
- Fresh bridge regeneration followed by Rust formatting has zero drift; Rust
  signatures and generated wire code stay unchanged.
- All 254 OpenMLS files reconstruct byte-for-byte. Eleven preparation/locking
  tests pass, including local-edit preservation, partial/deleted manifest
  protection, damaged caches, offline rebuild, dead-process recovery and
  multi-process exclusion.
- Changed instrumented executable lines, including moved source: Flutter
  267/300 (89.0%); core Rust 4,180/4,876 (85.7%). Comment/blank lines, generated
  bindings and tests are excluded. Preparation/locking coverage is 91.35% lines
  and 84.21% branches. Flutter/LLVM line reports do not expose branch coverage
  with the installed stable toolchains.
- Independent standards and requirements reviews found two Escape parity
  regressions and source-preparation recovery/edit-protection issues. Regression
  tests cover the fixes; documentation counts and module facts were reconciled.

Platform builds and physical adapter/audio behavior remain the existing CI and
hardware checks. A fresh native checkout needs the pinned archive or crates.io;
prepared/cached source supports offline builds. Materialized OpenMLS edits are
refused until converted into the tracked patch. This PR is not merged by the agent.
