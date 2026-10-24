# Issue 94: remove global protocol work from DM receipt commands

## Owner evidence

`callers-20261024-171047/mosh-callers-report.zip` has SHA-256
`5c245ceb103859ded5f2da20127991a20bdfcb9b4d2c4b9b76a8cb46f59a2039`.
PID 3792 and all five shipping binary hashes match the
[preceding CPU capture](issue-94-owner-cpu-20261024-153156.results.md), runtime
`82cc774e`. The original installer and matching PDB were retained privately.
The raw ETL remains on the owner's computer; its reported hash was not
independently recomputed here.

The selected caller export has 8,940 weights, including 3,514 with broken
unwinds; 853 foreign-process weights are excluded. The raw instruction export
has 8,936 weights: the four-weight difference is unresolved. Moss leaf-RVA
counts also do not reconcile exactly (1,923 caller versus 1,934 instruction
weights). Do not combine these denominators or claim exact conservation.

| Inclusive caller observation | Selected weights |
| --- | ---: |
| DM protocol tick, all callers | 666 |
| Shared mesh snapshot | 454 |
| DM mark-viewed command | 246 |
| Tick below mark-viewed | 158 |
| Receive below mark-viewed | 61 |
| Mesh query below mark-viewed | 68 |
| Strict Ed25519 verification, all callers | 14 |

These overlap and are sampled weights, not exclusive CPU milliseconds.
Strict verification previously appeared in 341 weights; the current export
does not justify further verifier changes. One inline iterator frame identifies
the enabled receipt branch, so optimizing only the disabled setting is insufficient.
The persisted setting over the entire recording is not established.

## Change and behavior checks

The UI already calls mark-viewed on each open-DM snapshot. Previously that
command serviced every saved DM before even checking the receipts setting.
Source `54135ec0` checks the setting first. Enabled commands receive updates,
retain the existing best-effort tail persistence, check selected-session access,
apply its deletions and send its receipts. They do not run the global protocol
tick, queued sends, retry timers or media synchronization.

Ordering of inbound frames and unread messages is unchanged. Receipt encryption,
deduplication and failed-send retry use the existing implementation; no RNG,
floating-point or tie-breaking change is included. Independent 500 ms service
continues normal maintenance. List/poll retain their fresh post-maintenance mesh
read. There is no TTL, new cache, public API, dependency, wire, storage, Flutter
or Moss change. Reverting the two receipt commits restores the old command.

The first two regression tests fail before the optimization: ten disabled
commands trigger ten global mesh queries; an enabled command triggers one.
Both pass after the change, while enabled receipt delivery and independent
service still succeed.

Independent review caught a missing persistence pass in candidate `36418394`.
The strengthened restart test fails there with `None` instead of `Some(true)`:
it receives a read receipt solely through mark-viewed and immediately restores
a fresh runtime, with no poll or tick masking a missing write. Keeping
`persist_tail_logged` fixes it without restoring protocol maintenance. The
final ten receipt tests pass, including encrypted delivery, forged/replayed
receipts, disabled symmetry, failed sends and immediate restart.

## Matched release comparison

Twenty alternating before/after pairs per setting use the same restored
fictional profile: eight offline DMs, one acknowledged message each. Workers
use the committed fat-LTO, one-codegen-unit release profile. Before is runtime
`82cc774e` / docs head `79981543` plus the same test-only receipt API commands;
after is `54135ec0`. Both load the identical isolated Go library with public
discovery disabled. Normal background service is enabled and its thread is
observed; no compiler or other local test runs during measurement.

Each of eighty fresh processes warms up for 25 cycles and measures 300 cycles
of list, selected-DM poll and mark-viewed: 24,000 measured cycles / 72,000 API
commands. Every cycle checks all complete message rows and session IDs against
the SHA-256 golden
`0df47e54aed4e7713b8e6348ff4ec5b55bda1467f8c7c6e8a1e46eaa0de6f4bd`,
the selected poll's messages and zero mesh peers. Receipt commands return the
same empty success result. CPU comes from process counters at 10 ms resolution;
latencies include the driver round trips and validation. Table entries are
medians over twenty processes for each variant and setting.

| Measure | Disabled before → after | Enabled before → after |
| --- | ---: | ---: |
| CPU / 300 cycles | 0.570 → 0.510 s | 0.570 → 0.540 s |
| CPU reduction | 10.5% | 5.3% |
| CPU range | 0.56–0.62 → 0.49–0.56 s | 0.55–0.62 → 0.53–0.62 s |
| Pairs with lower CPU | 19/20 | 17/20 |
| Wall / 300 cycles | 0.671 → 0.608 s | 0.678 → 0.650 s |
| Per-cycle p50 | 2.208 → 1.998 ms | 2.242 → 2.124 ms |
| Per-cycle p95 | 2.470 → 2.241 ms | 2.430 → 2.374 ms |
| Per-cycle p99 | 2.742 → 2.526 ms | 2.649 → 2.657 ms |
| Sampled RSS median | 53.16 → 52.51 MiB | 53.03 → 52.86 MiB |

All golden checks pass. Gains are limited; enabled p99 is essentially flat
and slightly higher. These are native command costs under controlled Linux
isolation, not a whole-Windows idle CPU or public-bandwidth result. The
[subsequent owner capture](issue-94-owner-cpu-20261024-194749.results.md) matches
the configured installer but does not establish whole-process improvement;
acceptance remains open.

Final-source formatting, build and all-target Clippy with warnings denied pass.
The final full Linux run via `node scripts/moss-test.mjs` passes: 779 library
tests with 20 ignored, plus all default-enabled integration targets, including
real multi-device DMs, history/recovery, revocation and idle reconnection.
The focused receipt suite passes ten tests plus its isolated directory worker.
LLVM coverage maps all 12 lines of mark-viewed as covered (21/24 regions).
Numerical branch coverage is unavailable; the three unexecuted regions are
implicit error returns delegated to existing helpers.

The first Windows CI attempt passes its 779 library tests but fails
`offline_identity_advertisements_follow_bounded_presence_retries` after the
counterpart restarts: a command returns beyond the 30-second delivery deadline.
Its idle limit passes (seven publications, maximum twelve). This scenario never
calls mark-viewed. It passes unchanged on Linux and macOS. An old-generation
replay is also logged, which alone does not establish the timeout's cause.
The same-source Windows job passes on its sole repeat, without changing the
test. Its intermittent cause remains unestablished. All thirteen enabled jobs
pass across attempts of [source CI 40118014255](https://github.com/redstone-md/mosh-flutter/actions/runs/40118014255),
including Windows/macOS core, real device linking and multi-device DMs, native
audio/video on three platforms, Flutter, bridge drift, Windows UI/installer and
macOS menus/DMG. No merge or release is included.

## Standards review

The read-only Standards review of final tree
`3ca8f81987d5a2d93c982638ee40b507f1ea7d29` reports zero actionable findings.
The existing receive, authorization, deletion and persistence owners
are reused; test support extends the existing public-API process driver.

## Spec review

The initial persistence finding is fixed and verified red/green. The final
immutable tree has zero remaining actionable spec findings. Independent service
and external contracts remain unchanged. Issue 94 remains open for desktop
acceptance and physical Android background-call/battery work.

## Configured Windows installer

[Full-release build 40118006925](https://github.com/redstone-md/mosh-flutter/actions/runs/40118006925)
passes on source `54135ec0`, including native window tests. It uses the committed
fat-LTO, one-codegen-unit profile and the existing production mainnet billing
origin and issuer pin. Both downloaded artifact ZIP digests match GitHub metadata.

The installer is `mosh-0.24.1-setup.exe` from
[artifact 12569834437](https://github.com/redstone-md/mosh-flutter/actions/runs/40118006925/artifacts/12569834437).
Its SHA-256 is
`3548089b54f521f70bcd3e0cea999a21ca6d1eb65c84f51e40c55c6e1edcc5c8`.
All five extracted shipping hashes match the source manifest. The original Rust
DLL and PDB match their manifest hashes and CodeView GUID/age:
`5645F208-7221-4831-8517-FC6981546888`, age 1. Original binaries and symbols are
retained privately. The extractor reports 63 multi-part readback warnings;
the independent shipping-hash checks pass, without a claim about every asset CRC.

For owner acceptance, quit through the tray before installing. Reopen the same
profile/offline chat, allow ten minutes to settle, then use the existing
`Start-CPU.cmd` and send its `mosh-cpu-report.zip`. This records the installed
hashes and both CPU and network. The previous existing-trace exporter pins the
older source/PDB and must not attribute the new build.
