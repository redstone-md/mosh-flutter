# Issue 94: compare verified roster prefixes directly

The owner's existing Windows trace, exported in callers-20261023-035305,
matches all five cd6df31b binaries and conserves 9,924 selected-PID weights.
Another 1,154 weights are excluded as foreign. DeviceRoster::extends appears
in 263 weights, including 213 in digest generation below it. This comparison
currently clones a prefix and serializes/hashes both rosters to test equality.

Scope: compare the private Authorization entries directly after the existing
full-chain verification. No cache, skipped verification, wire/storage changes,
new dependencies, bridge changes or Moss edits. Keep digest generation for
signed parent hashes and all other protocol uses unchanged.

Opportunity: impact 2, confidence 5, effort 1, score 10. Identity decoding and
network-interface enumeration are separate measured costs. This change cannot
claim to solve total owner CPU, traffic, rendering or Android background work.

1. Add a regression at the admission/revocation caller: warmed, unchanged
   authorization reads must not rebuild roster digests. Observe RED first.
2. Compare valid prefixes, forks, removals/re-additions and malformed chains
   with the old implementation. Capture serialized rosters and hash goldens.
3. Implement private entry equality and slice-prefix comparison, retaining
   verification before the comparison. Ordering and errors remain unchanged;
   floating point and random behavior are unaffected.
4. Measure release-mode old/new comparisons and existing native API workloads
   using identical fixtures, binaries/dependencies and outputs. Do not use a
   microbenchmark to predict whole-Windows savings.
5. Run Rust build/tests/format/Clippy, relevant real device/DM checks and the
   generated-bridge drift check when required. Review both Standards and Spec,
   publish results, commit and update PR 96. No merge/release.

Raw traces and fictional fixture stores/keys stay private. Rollback is one
runtime commit revert. Any changed authorization result blocks this change.
