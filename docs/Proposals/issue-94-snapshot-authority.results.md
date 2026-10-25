# Issue 94: local actor validation per history snapshot

## Evidence and change

The [configured Windows GUI profile](issue-94-snapshot-authority.plan.md)
finds repeated local ownership-proof work below history snapshots. This is
independent evidence from the original `54135ec0` installer; it does not
establish the owner's remaining whole-process CPU or memory cause.

Runtime source `aa17f31e`, tree
`04bf3b81e24467b9d8088078aaa7277780bd8445`, introduces a private borrowed
permission evaluator for one immutable history snapshot. It lazily evaluates
the current local actor once, then keeps all per-message origin, author and
admin checks. A new snapshot evaluates current membership and revocation again.
Direct deletion commands create a fresh evaluator. Empty or ineligible
histories do no extra actor work. There is no global authorization cache,
bridge, wire, dependency, storage, Flutter, discovery or Moss source change.

The regression compares complete expected message rows before asserting its
work bound. On the preceding implementation the rows already match but local
revocation/proof checks are 16 instead of one. The candidate passes with one.
The additional lazy-storage test also passes. Existing cases preserve changed
proofs, lost roles/membership, revoked issuers and forged-origin rejection.

## Matched release comparison

Twenty alternating before/after pairs per scenario use freshly restored
fictional stores. Before is `54135ec0`; after is `aa17f31e`. Both frozen workers
use the committed fat-LTO, one-codegen-unit release profile and the identical
isolated Go library with public discovery disabled. Normal 500 ms background
service is enabled and observed. No compiler or other local test runs during
measurement; unrelated host services remain active. The host is a Linux
AMD EPYC 7713 VM with sixteen logical processors.

The short fixture has eight acknowledged offline DMs with one message each.
The long fixture has one acknowledged offline DM with 201 messages, including
200 delegated origins. All 201 messages are owned and deletable. This exceeds
the owner's reported maximum of about 100 messages; it is a scaling fixture,
not an exact reproduction of the owner's complete profile.

Each of eighty fresh processes warms up for ten list calls, then measures
300 calls for the short fixture or 120 for the long fixture: 16,800 measured
calls. Every call checks complete message rows and permission metadata,
attachment rows and session IDs against the same before/after golden, and
asserts zero mesh peers. CPU is measured in the worker at 10 ms resolution;
wall latency includes driver round trips and JSON validation. Table values
are medians over twenty processes per variant and scenario.

| Measure | Eight one-message DMs | One 201-message DM |
| --- | ---: | ---: |
| Calls per process | 300 | 120 |
| CPU before → after | 0.350 → 0.350 s | 0.495 → 0.430 s |
| CPU reduction | 0.0% | 13.1% |
| CPU range | 0.34–0.41 → 0.34–0.39 s | 0.47–0.58 → 0.41–0.46 s |
| Pairs with lower CPU | 8/20 | 20/20 |
| Wall time | 0.430 → 0.431 s | 0.865 → 0.799 s |
| Per-call p50 | 1.405 → 1.411 ms | 7.116 → 6.606 ms |
| Per-call p95 | 1.506 → 1.542 ms | 8.034 → 7.263 ms |
| Per-call p99 | 1.636 → 1.625 ms | 8.259 → 7.822 ms |
| Sampled RSS median | 54.70 → 53.69 MiB | 50.95 → 50.92 MiB |

All golden checks pass. SHA-256 is
`e2e1ad6fa6ec187db9849ac42e58757ec0481fe2c72e8d7084881c3e80eef57f`
for the short fixture and
`90f070ddb6760ea781dbd0b7c75ca414bd99a61612d1ea3670fa89c805873906`
for the long one. The short fixture has no median CPU gain and slightly higher
p95 latency. RSS samples do not establish retained allocations or leak behavior.
The initial harness expected an unavailable API field and stopped before timing;
it was corrected to the actual stable fields before these eighty processes.

This comparison supports lower native history cost at larger histories.
It does not measure whole-Windows idle CPU, public-network traffic or Android
battery consumption. The remaining per-origin parsing and full list
serialization are unchanged.

## Verification

Formatting, build, all-target Clippy with warnings denied and documentation
tests pass. All 781 library tests pass (20 ignored). All default-enabled native
integration targets pass across the full run and continuation. The first
idle-reconnection integration attempt exceeds its post-restart delivery deadline;
the idle announcement bound itself passes. Its sole unchanged-source rerun
passes, without a retry loop or weakened assertion. The same scenario has
previously failed intermittently on Windows. Its cause is not established.

The focused LLVM coverage run passes all 36 deletion-domain tests. All 79
changed mapped lines are covered: 22 in authority, four in snapshot, four in
test-only instrumentation and 49 in the new regressions. Numerical branch
coverage is unavailable with the pinned stable toolchain.

## Standards review

The independent read-only review of immutable runtime `aa17f31e` has zero
findings. It confirms feature-local scope, existing authorization owners,
size limits and the focused full-row/lazy regressions.

## Spec review

The independent read-only review of the same runtime has zero findings.
The authority cannot mutate during its borrow; validation cannot survive into
the next snapshot. Direct commands retain fresh checks. No public contract
or permission rule changes.

## Acceptance limits

The [latest owner capture](issue-94-owner-cpu-20261024-194749.results.md)
does not prove a whole-process improvement. Its already-high working set
does not establish a leak over ninety seconds. Its matching caller export is
now processed in the Windows follow-up below.

Issue 94 stays open for desktop CPU/network acceptance and physical Android
background-call/battery work. No merge or release is included.

## Independent Windows follow-up

The [configured-GUI follow-up](issue-94-owner-callers-20261024-221402.results.md)
passes on the actual `aa17f31e` installer, preserving all 800 acknowledged
message bodies and the eight-DM/two-group/one-channel inventory. It records
10.563%/8.975% one-core CPU and 0.152/0.097 Mbit/s in separate visible/minimized
public-mesh windows. These observations do not establish whole-Windows CPU
improvement, reproduce the owner's higher working set or close owner acceptance.
The owner's old-trace caller export also matches `54135ec0`; it is not an after
measurement of this correction. Its processing is complete, without needing
another export of the same ETL.

The subsequent [owner recording on `aa17f31e`](issue-94-owner-cpu-20261024-230853.results.md)
matches all five release binaries. Observed CPU is 0.654% across sixteen
logical processors versus 0.678% previously. Mean traffic falls to 0.452
Mbit/s while the median is almost unchanged; working set decreases during
the interval. These uncontrolled observations do not establish whole-process
patch gains or a memory-leak cause. Owner acceptance remains open.
