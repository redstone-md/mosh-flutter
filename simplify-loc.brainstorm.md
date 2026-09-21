# Brainstorm — Repo-wide simplification, 30%+ LOC drop

## Problem

The codebase carries three kinds of bloat:

1. **Port archaeology comments.** The Flutter fork was ported from a dead
   React/Tauri app. Hundreds of files carry "React did X -> Flutter does Y"
   mapping comments, CSS-class archaeology, `aria-*` mapping tables, and
   1-to-1 port notes. 1,061 lines in `lib/src` mention React/Tauri/1-в-1;
   7,089 of 27,261 handwritten Dart-lib lines are comments (26%). AGENTS.md
   wants comments a first-pass reader understands — archaeology is noise.
2. **Runtime copy-paste.** `private_dm_runtime.rs` (4,419), 
   `private_group_runtime.rs` (4,071) and `channel_runtime.rs` (1,426)
   re-implement the same machinery per kind: typing constants + event pushes,
   attachment facade methods, outbox/ack pumps, session maps, drain/route/tick.
   Repo policy caps files at 400 LOC; these are 10x over.
3. **Test scaffolding duplication.** 21,720 Dart test LOC with repetitive
   pump/settle/assert scaffolding per file.

## Options

**A. Single monolithic PR.** Fast, no ordering issues, but unreviewable and
risky to bisect.

**B. Stacked PR series by concern.** Each PR is one coherent slice, green on
its own, reviewable independently, mergeable in order. Conflicts avoided by
stacking branch N+1 on branch N.

**C. Only comments + docs, skip structural work.** Hits maybe 12% — under
target, leaves god files.

## Chosen direction

**B — stacked PR series**, ordered so the mechanical no-risk PR lands first:

1. `comments` — strip React/Tauri archaeology from Dart lib+tests (pure
   deletion; analyze must stay clean).
2. `core-unify` — unify duplicated runtime machinery (typing, read events,
   session plumbing) into shared `conversation/` modules.
3. `core-split` — break the three runtime god files into 400-LOC modules
   (repo policy), delete dead code found on the way.
4. `ui-simplify` — Dart feature consolidation: split/slim media_viewer,
   attachment_card, unify duplicated header/menu/branching patterns, collapse
   if-if-if chains into data-driven dispatch.
5. `test-consolidate` — shared test scaffolding, delete repetitive per-file
   copies without losing assertions.
6. `docs` — Architecture.md truth pass (stale "five todo!() stubs" claim),
   module map for the new layout, CHANGELOG.

## Risks

- Rust refactor must be behavior-identical: mitigated by the existing runtime
  test suites (state/outbox/history/transfer/runtime/api tests) run per PR.
- Generated bridge (frb_generated) must not drift: no `api::` signature
  changes in any PR; CI drift gate stays green.
- Comment stripping must not delete load-bearing "why" notes (crypto
  constants, cross-file paired timeouts). Those stay, rewritten plainly.

## Target math

Handwritten baseline ≈ 82,300 LOC (Dart lib 27.3k, Dart tests 21.7k, Rust
28.1k, Rust tests 3.75k, probe 1.4k). 30% ≈ 24,700 lines to remove.
Sources: ~5.5k comments, ~4k runtime unification, ~2.5k Dart consolidation,
~3k test consolidation, ~2k Rust comment trim + dead code, remainder from
de-duplication found along the way. Generated code (frb) is out of scope and
excluded from the ratio.
