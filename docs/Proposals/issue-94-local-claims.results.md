# Issue 94: unchanged local identity claims

Whole-Windows idle acceptance remains open. This follow-up removes repeated
local claim signing in Mosh. It changes no Moss source, discovery policy,
publication schedule, public API, wire format, dependency or stored schema.

## Exact-binary owner capture

The owner supplied `cpu-20261022-195633/mosh-cpu-report.zip`, SHA-256
`ce7bd8de6d2ecea4ced261ed27d04436bb1d41d2f26e83548d84f1ac8b882e09`.
All five shipping binary hashes match the configured installer from run
39812473672: source `56d2dc4a`, including the account-certificate correction,
and Moss `eb79f38`. The 90.729-second interval starts at
2026-10-22T19:57:04.6016434Z, approximately twenty-nine minutes after process
startup. Hardware remains Ryzen 7 6800H with sixteen logical processors and
Windows 10.0.26200.0. Capture completeness and control checks pass; all event
and buffer loss counts are zero. Second and endpoint byte totals reconcile.

| Whole-process observation | Value |
| --- | ---: |
| CPU, one logical core | 11.172% |
| CPU normalized over sixteen logical processors | 0.698% |
| Working-set median | 98.13 MiB |
| External TX / RX | 3,910,317 / 6,495,728 bytes |
| Combined network mean | 0.918 Mbit/s |
| Complete-second median / p95 / peak | 0.337 / 2.260 / 10.628 Mbit/s |

The owner's contemporaneous snapshot reports 23 direct neighbors, no relayed
neighbors, 30 relay-capable directory entries and 483 known peers. Capability
entries are not thirty active relays; relayed-neighbor count also does not
describe every possible transit route. This alone does not justify a hard
connection cap.

CPU and mean traffic are lower than the previous capture's 15.466% and
2.278 Mbit/s. Public topology, traffic and GUI/history state are uncontrolled,
so these differences are observations rather than causal patch percentages.
No complete-second bucket reaches the reported 100–150 Mbit/s rate; subsecond
bursts are not measured by these aggregates.

Approximate alignment of 88 process-counter intervals with one-second byte
buckets gives CPU/traffic correlation 0.765. The lowest-traffic quartile has
median 0.209 Mbit/s and 9.25% of one core; the highest quartile has median
1.574 Mbit/s and 12.31%. Bucket overlap assumes uniform traffic inside each
second and cannot identify a causal function or a traffic-free CPU baseline.

## Attribution

The original, co-produced Rust PDB matches the shipping DLL's CodeView identity
and resolves all 1,997 Rust instruction weights. Of 10,520 total statistical
weights, Rust accounts for 18.98%, Moss for 21.21%, the principal kernel module
for 21.22% and Flutter for 9.05%. These weights are not exact CPU milliseconds.
Curve arithmetic leads Rust's leaf and outermost-inline rankings. Recovered
Go ranges map 2,239 of 2,240 raw Go instruction weights; one remains unmapped.
Shared curve functions can serve different callers, so the flat Windows
profile does not establish that all such work is claim signing.

Go `MeshInfoJSON` has 47 sampled instruction weights, approximately 0.45% of
the total. This measures that symbol's own sampled instructions, not its entire
inclusive cost. It remains a possible secondary cost, without evidence here
that it dominates CPU or causes the residual bandwidth.

A separate Linux release caller profile restores the existing fictional
8-offline-DM/2-group/1-channel fixture. All eight DM messages are acknowledged.
A private compiler overlay disables public discovery in both variants; zero
mesh peers are asserted. Both public API workers retain their normal background
DM service, alongside list-driven device preparation and protocol work.
The twenty-second baseline has 3,548 samples and zero lost samples. Inclusive
`current_device_claim` work accounts for about 18.01%; its nested claim creation
is 14.49%. `DeviceIdentity::open` accounts for about 33.06% across its callers.
Nested percentages must not be added. This identifies a reproducible local
claim opportunity, not a whole-Windows CPU budget.

The corresponding twenty-second after profile also loses no samples.
`current_device_claim` falls to 5.36% of inclusive sampled work, and the fresh
claim-signing path disappears from the reported caller ranking. Remaining
identity loading accounts for 39.68% of the changed profile mix. This busy-loop
profile completes 8,054 polls versus 6,717 before in the same twenty seconds;
its relative shares do not establish an absolute regression in identity loading.

## Reproduced cause and correction

Every receive/service entry prepares session device state. Refresh constructs
and signs the local claim before checking for an unchanged roster. Advertising
also signs before its existing unchanged-publication check. Ten unchanged
refresh/advertisement cycles increase actual signature count from two to
twenty-two, despite emitting no additional advertisement frames.

Commit `a640f75a` retains one SHA-256 signing-input digest and its locally
generated deterministic signature per DM session. The input includes context,
session, full roster, device ID, MLS signer and display name. A changed input
signs again and replaces the single slot. Fresh roster-extension and current
device-membership checks run before every lookup. No permission decision,
private key or persistent cache state is retained. Existing selected-roster,
removal and publication logic remains in place.

Both the ordinary signing path and the reusable path share the same unsigned
claim builder. Tests compare actual wire bytes, verify changed-input misses and
slot replacement, and reject current device revocation after warming. The
caller-level regression preserves actual frame counts and removes repeated
signing on unchanged refreshes.

## Matched release comparison

Twenty pairs alternate before/after order, restoring the identical encrypted
fixture before each of forty fresh processes. Each process warms once and then
performs 300 real list API calls. More calls keep the ten-millisecond process
CPU counter resolution small relative to measured work. Both workers load the
same private isolated Go library, verified in `/proc`, with all messages
acknowledged and zero mesh peers asserted throughout. No compilation or host
tuning occurs during these measurements. Before source is `a7bd4b93`; after
source is `a640f75a`.

| Per-process measurement for 300 reads | Before | After |
| --- | ---: | ---: |
| Median CPU | 0.800 s | 0.700 s |
| CPU range | 0.790–0.880 s | 0.680–0.750 s |
| Median total wall time | 0.875 s | 0.769 s |
| Median of per-process median call times | 2.754 ms | 2.408 ms |
| Median of per-process p95 call times | 3.017 ms | 2.617 ms |

Median CPU decreases **12.5%**, with lower CPU in every pair. All returned
message fields, including content, origin, identity and permission metadata,
match at every measured read in all processes. Their canonical digest is
`0df47e54aed4e7713b8e6348ff4ec5b55bda1467f8c7c6e8a1e46eaa0de6f4bd`.
This is a controlled native API result, not a rendered Windows idle or network
acceptance result. Synthetic fixtures, raw profiles, keys and owner traces
remain private.

Method correction for earlier reports: `MOSH_DM_MANUAL_SERVICE=1` was supplied
equally, but only the raw-runtime test worker honors it. These measurements use
the public API worker, which starts the normal 500 ms background DM service.
The matched measurements therefore include background work in both variants;
they do not establish timings with that service disabled. Earlier history
measurements are described accordingly in the linked report.

### Paced open-chat check

Three further pairs restore the same fixture, with both variants active at
once and alternating construction/poll order. Each warms for thirty seconds,
then measures ninety seconds. Once per second, each calls personal names,
DM list, group/channel lists twice and the selected offline DM poll. The
normal `mosh-dm-service` thread is observed in every process. Public discovery
is disabled by the same private Go overlay; mesh counts remain zero. Every
returned group/channel inventory retains two groups and one channel, and all
DM message digests still match.

Median CPU is **1.844% → 1.711% of one core**, a 0.133 percentage-point / 7.23%
relative reduction. Before ranges 1.667–1.956%; after ranges 1.478–1.711%.
Every pair improves, but only three pairs are measured and ranges overlap.
This supports local savings with background service and paced reads; it does
not predict public-network Windows idle CPU or measure network savings.

## Checks and remaining acceptance

The signature-count regression fails before the fix (twenty-two versus two)
and passes after it. Focused device checks pass 23 tests with seven expected
ignored workers. All 756 unit tests pass with twenty expected ignored workers;
all-target Clippy with warnings denied, formatting and diff checks pass.
LLVM coverage maps all 40 changed executable production lines (100%) and all
109 changed executable test/instrumentation lines. The latter include four
test-only counter lines in the production module; branch data is unavailable.
Independent Standards and Spec reviews of `a7bd4b93...a640f75a` report no
actionable findings. CodeAnt completes its incremental `a640f75a` review with
no unresolved inline findings or nitpicks; all thread/comment pages are checked.

The complete [application CI at `a640f75a`](https://github.com/redstone-md/mosh-flutter/actions/runs/39847461710)
passes all thirteen active jobs: both Rust lanes, Flutter, codegen drift,
multi-device DM, device linking, Windows bridge UI, native audio/video on all
three desktop platforms, Android arm64 debug and Windows/macOS packaging.
Android release is intentionally skipped on PRs. Subsequent reporting changes
only add these results and correct earlier measurement wording.

## Configured Windows installer

The [configured Windows EXE](https://github.com/redstone-md/mosh-flutter/actions/runs/39848146470/artifacts/12458760624)
is built from `a640f75a` with the committed release profile; the proof-build
parallel-codegen override is disabled. Source/Moss pins, PE header, SHA-256
sidecar and production PLUS manifest checks pass, and the installer workflow
finishes successfully. The setup file is 55,793,156
bytes with SHA-256
`7da0d064e67cc53ed510fb4e2a22b97b00937711478e526d12bfad1b703dcffe`.
All five extracted shipping binaries match the co-produced symbols manifest.
The original Rust DLL/PDB CodeView GUID is
`{60BA9EA1-9FAA-49AC-986F-DD36BA8E52D6}`, age one; the PDB hash and debug identity
match. The original PDB is retained privately for subsequent owner captures.

Moss stays at `eb79f38`. Its Go 1.25.9 DLL embeds the parent Mosh revision and
therefore changes hash on this rebuild; that embedded revision is not the
Moss gitlink. This bundle is not presented as a one-binary Windows comparison.

Device identity loading/validation, full snapshot serialization and incoming
public mesh work remain separate costs. This correction does not establish
acceptable whole-application CPU, bandwidth or Android battery use. Issue 94
stays open, including Android background calls. No merge or release is included.

The subsequent [loaded-key follow-up](issue-94-identity-key.results.md) analyzes
the exact `a640f75a` owner capture and removes redundant public-key construction
inside each loaded identity, while preserving fresh validation and revocation
checks. Its comparisons use `a640f75a` as the before variant.
