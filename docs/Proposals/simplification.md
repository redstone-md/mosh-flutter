# Repository simplification

Scope: Flutter UI and state, Rust runtime and storage, native probes, build
tooling and architecture documentation. Preserve product behavior, bridge
contracts, database tables, dependency versions and cryptographic checks.
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
storage contracts. Dependency versions and database tables are unchanged.
Review fixes add backwards-compatible metadata to encrypted organization records
to remember dismissed offers and recover unfinished accepted joins.

| Scope | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| All tracked source, including local patches | 223,340 | 146,052 | 34.61% |
| Dependency source and patches | 83,795 | 6,127 | 92.69% |
| Application and tooling | 70,866 | 66,730 | 5.84% |
| Tests | 45,170 | 49,693 | +4,523 lines |
| First-party source and tests together | 116,036 | 116,423 | +387 lines (0.33%) |
| Generated bridge | 23,509 | 23,502 | 7 comment lines |
| All tracked UTF-8 text, including docs/manifests | 262,151 | 179,646 | 31.47% |

The overall reduction exceeds 30%. Most of it replaces an upstream mirror with
reproducible preparation; it does not shrink OpenMLS at runtime. Application and
tooling shrink less; added recovery and review regressions increase the authored
test count. These totals include comments and blank lines. No feature, test case
or cryptographic check was removed to
reach the target. Inline Rust tests moved into named files, explaining why the
separate application and test categories should not be interpreted in isolation.

Largest runtime roots: DM 1,072 → 373; group 1,045 → 364; channel 468 → 342;
organization 963 → 350; MLS adapter 871 → 91; probe main 1,429 → 50.
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

## PR review follow-up

All 18 inline CodeAnt findings and the general comment's eight nitpicks were
validated. Thirteen inline findings and seven nitpicks have complete fixes:
retained scripted bridge state, one initial viewed command, native admission
cleanup, attachment dimensions, MLS tree serialization before merge, bounded
probe retries and real-receiver receipt/typing proofs with restored global test
state.

Organization acceptance now prepares a native join, durably registers its
original keys and offer, then publishes and polls. A refused registration
publishes nothing. Failed publication and restart retain an offer that can retry
the inviter's cached Welcome. Native record and MLS snapshot writes atomically
retire the matching recovery backup; cached org writes preserve that resolution.
No second organization write follows successful native admission. Group creation
validates targets first and returns the created group while attempting every
invitation, so one publication failure does not hide a durable group.

Five inline threads remain open. Two suggestions are disproved by the pinned
OpenMLS implementation and the passing Windows corrupt-cache test. Three
identity findings need a protocol migration: plain-group DM offers lack sender
authentication, and attachment/typing Moss identity claims are not bound to the
authenticated MLS member. Matching outer and inner attachment identities rejects
inconsistent claims but cannot stop a member forging both. Resolving these fully
requires a Moss-to-MLS identity binding and compatible wire migration; the
existing public contracts are preserved here.

## Verification

- Flutter analysis and formatting pass; the final full suite passes 1,323 tests
  with five existing skips. Held/modified Escape regression cases failed before
  the fix and pass after it.
- Core build, formatting, strict all-target Clippy and full real-Moss Cargo tests
  pass: 547 top-level tests and 21 existing ignores, plus subprocess workers.
  The same complete suite passes under LLVM coverage. Probe unit tests pass
  (four cases) and strict all-target Clippy passes. Thirty-one fresh real local probe
  CLI checks cover DM, simultaneous DMs, groups, admin succession, doctor,
  argument errors and timeouts; changed probe lines cover 857/875 (97.94%).
- Fresh bridge regeneration followed by Rust formatting has zero drift; Rust
  signatures and generated wire code stay unchanged.
- All 254 OpenMLS files reconstruct byte-for-byte. Twelve preparation/locking
  tests pass, including local-edit preservation, partial/deleted manifest
  protection, damaged caches, offline rebuild, dead-process recovery and
  multi-process exclusion and drive-style archive paths. The latter reproduced
  the Windows setup failure before the extraction fix; all twelve cases also
  pass with automatic CRLF conversion enabled in Git configuration. Windows
  readers can briefly block claim replacement; bounded retries preserve the
  choosing claim until publication succeeds. Cleanup waits for every test worker.
- Changed instrumented executable lines, including moved source: Flutter
  272/305 (89.18%); core Rust 5,016/5,671 (88.45%). Comment/blank lines, generated
  bindings and tests are excluded. Preparation/locking coverage is 90.18% lines
  and 82.89% branches. Flutter changed branches cover 48/53 (90.57%); Rust branch
  coverage requires nightly, unavailable in the installed stable toolchain.
- Independent standards and requirements reviews found two Escape parity
  regressions and source-preparation recovery/edit-protection issues. Regression
  tests cover the fixes; documentation counts and module facts were reconciled.

Platform builds and physical adapter/audio behavior remain the existing CI and
hardware checks. A fresh native checkout needs the pinned archive or crates.io;
prepared/cached source supports offline builds. Materialized OpenMLS edits are
refused until converted into the tracked patch. This PR is not merged by the agent.

The probe channel listener retains an existing exit race: after receiving it
can exit before the sender retries a `NoPeers` result. The original unsplit CLI
reproduces it against the same current core. Keeping a real recipient alive
verifies the body and successful sender verdict; this refactor preserves that
command behavior.
