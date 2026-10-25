# Issue #94: direct-peer wait experiment

## Decision and scope

The event-driven wait substantially reduces allocations against the
context-aware Moss revision currently pinned by Mosh. Keep the change in
[Moss PR #30](https://github.com/redstone-md/moss/pull/30), stacked on
[PR #29](https://github.com/redstone-md/moss/pull/29). Do not merge it directly
onto the older main implementation: the separate control below increases
allocations against that implementation.

This is a verified improvement to one waiting path. It does not establish a
whole-Mosh CPU reduction or complete issue #94's desktop/Android acceptance.
No Mosh dependency pin, release or deployment changes in this experiment.

Source identities:

- Shipping baseline: Moss `979a63459e7327aec5a318b108d0382a8f5b091c`.
- Measured shipping candidate: `a52072b1a0d141b1d8f98b2a30347c882f4d8856`.
- PR #30 candidate: `fcdc3383601cf3fb5232ba1ae1ffe262b552555e`.
- The measured candidate and PR head have identical runtime source. Their
  differences are documentation and deterministic synchronization in a test.
- Benchmark harness: Mosh `9b403efeb68a71ed487cb8f399903c5c764f4150`.
- Public reprofile harness: Mosh `f5c7865bf0265e3e31a243a8866d16840e77cd89`.

## Behavior and verification

The shipping context-aware wait creates a fresh `time.After` every 25 ms while
checking for a direct peer. The candidate subscribes under the node mutex,
wakes when direct registration closes its notification, and uses one deadline
timer. Every wake rereads the present, non-relayed peer predicate. Reference
counts and notification identity checks release the final waiter without
deleting a newer subscription.

The change preserves public APIs, authentication, handshakes, discovery
policies, retries and existing cancellation-aware callers. No feature flag or
Mosh-specific public contract is introduced.

- The initial registration regression failed on polling code: a registered
  direct peer left waiters blocked until the next tick. It passes with the
  notification implementation without advancing virtual time.
- Tests cover multiple waiters, relayed/unrelated peers, immediate readiness,
  cancellation, deadlines, zero/negative timeouts, transient direct removal,
  subscription cleanup and node-bound shutdown.
- Focused race tests passed 20 repetitions. The four functions in
  `node_direct_wait.go` have 100% statement coverage; numeric branch coverage
  is unavailable from Go's coverage tool.
- Shipping explicit-target/room-policy regressions passed under `-race`.
- `go vet ./internal/mesh` passed. The final stacked source passed the full
  local suite with Go 1.25.9, `GOMAXPROCS=2`, `go test -p 2 ./... -count=1
  -timeout 1800s`; mesh took 284.885 seconds and FFI 96.216 seconds.
- [Final-head CI](https://github.com/redstone-md/moss/actions/runs/40150783981)
  passed all eight jobs on `fcdc338`: Linux/Windows full suites,
  fast-package and mesh race checks, strict
  mesh, three mesh repetitions, a 25-node load scenario and a memory gate.
- Independent Standards and Spec reviews found no issues in the final diff.
- CodeAnt's one summary nit correctly identified a test scheduling gap.
  `0af1b78` replaced the probabilistic loop with deterministic subscription
  synchronization. No unresolved inline CodeAnt threads were present.
  CodeAnt's reviewed revision was `ed3bb13`, not a final-head approval.

## Paired Windows method

Each comparison compiles both optimized Go test executables before measurement
on one Windows runner, using Go 1.25.9, `CGO_ENABLED=0`, amd64/v1 and
`GOMAXPROCS=4`. The baseline receives the same benchmark and CPU-counter helper;
its runtime implementation is unchanged.

After one warmup per executable, 20 pairs alternate before/after and
after/before ordering. Each process reports five measured batches after an
initial calibration batch; a batch concurrently waits one second for eight
absent peers. All 1,600 measured wait outcomes per
comparison are false. The benchmark has no public network, FFI, Flutter,
database, discovery or handshake workload.

Each ZIP has 46 expected files: fingerprints, toolchain information, pair order,
summary and 42 process outputs. Download validation checked the API artifact
SHA-256, ZIP CRC, exact member names, source revisions, toolchain, pair order,
batch counts and outcomes. No executables or private traces are published.

## Shipping baseline: primary result

[Run 40150096953](https://github.com/redstone-md/mosh-flutter/actions/runs/40150096953),
[artifact 12581684527](https://github.com/redstone-md/mosh-flutter/actions/runs/40150096953/artifacts/12581684527).
Host: AMD EPYC 7763, two cores/four logical processors, Windows Server 2025
10.0.26100, runner image `20261021.278.1`.

Medians below are per batch of eight waits, not per individual wait:

| Metric | Shipping `979a634` | Candidate `a52072b` |
| --- | ---: | ---: |
| Elapsed milliseconds | 1012.40310 | 1000.38377 |
| OS process CPU milliseconds | 3.125 | 0 |
| Allocated bytes | 81,878 | 6,375.5 |
| Allocations | 974.5 | 60 |

Allocated bytes fell approximately 92.2%; allocation count fell 93.8%.
Every pair improved both metrics. The median paired differences are
-75,734.5 bytes and -915.5 allocations. CPU was lower in 14 pairs and tied in
six; no pair increased CPU.

`GetProcessTimes` is quantized: the five-batch average exposes 3.125 ms steps
on these runs. A recorded zero means below that counter's resolution, not
zero CPU or a 100% saving. The timeout timing difference removes polling
overshoot; it does not change the requested one-second deadline. These results
do not quantify CPU, memory or traffic savings for the complete application.

Artifact SHA-256:
`3c8b3aea649c6b38efafa8dfd8274f4442d91e22aff3a5f25c36c8e40f120312`.
Baseline executable:
`c3870cc273af6d622b1b0a8fdb2333a3539d89da96dfe0d023893f50d56e4ce2`.
Candidate executable:
`5d98f83bb951c2c39a8a13e57d826fbca2d2451656d5dbfbb6558d8df4c6b959`.

## Older-main control: allocation regression

[Run 40149982873](https://github.com/redstone-md/mosh-flutter/actions/runs/40149982873),
[artifact 12581634215](https://github.com/redstone-md/mosh-flutter/actions/runs/40149982873/artifacts/12581634215).
Host: AMD EPYC 9V45, two cores/four logical processors; same Windows version,
runner image, toolchain and measurement procedure as above.

| Median per batch | Older main `8eb416d` | Candidate `ed3bb13` |
| --- | ---: | ---: |
| Elapsed milliseconds | 1011.65163 | 1000.34044 |
| OS process CPU milliseconds | 0 | 0 |
| Allocated bytes | 2,988.5 | 5,865 |
| Allocations | 20 | 58 |

Allocations increased in all 20 pairs; median paired differences are +2,909
bytes and +38 allocations. CPU improved in five pairs and tied in 15, with no
median CPU improvement established. Older main uses `time.Sleep`, which reuses
the goroutine's runtime timer. It does not allocate a fresh `time.After` for
each check. The notification bookkeeping costs more than that older wait.

This negative control is why PR #30 targets PR #29's context-aware baseline.
The two comparisons run on different hosts and baselines; combining them into
one gain or claiming a general improvement over older main would be invalid.

Artifact SHA-256:
`07e44ef5e4049abf5c3140c1fcde85550ac22a2fa8c825ceeebb609c8a0521d5`.

## Public-network reprofile

[Candidate run 40150158645](https://github.com/redstone-md/mosh-flutter/actions/runs/40150158645),
[artifact 12581868533](https://github.com/redstone-md/mosh-flutter/actions/runs/40150158645/artifacts/12581868533).
The standalone Windows Go probe uses the same configuration content as Mosh
`aa17f31e`, eleven rooms, eight known offline DM policies, 33 subscriptions and
an eight-minute warmup. Both phases last 90 seconds. The only experimental
runtime substitution is Moss `a52072b`.

Host: AMD EPYC 9V74, two cores/four logical processors; Windows Server 2025
10.0.26100, image `20261021.278.1`, Go 1.25.9, `GOMAXPROCS=4`.

| Candidate observation | Mesh reads enabled | Service only |
| --- | ---: | ---: |
| Scheduled mesh reads | 539 | 0 |
| OS process CPU seconds | 1.750000 | 0.343750 |
| CPU as one core percent | 1.9444% | 0.3819% |
| Go CPU sample seconds | 1.49 | 1.27 |
| Total allocated bytes during window | 75,515,136 | 33,816,864 |
| GC cycles during window | 31 | 14 |
| Heap allocated bytes, before → after | 5,406,448 → 3,795,968 | 6,844,272 → 3,708,984 |
| Connected peers, before → after | 14 → 14 | 14 → 16 |

The candidate CPU profiles contain no `waitForDirectPeerContext` sample, and
the cumulative allocation profiles contain no matching allocation sample.
Neither final goroutine snapshot contains an active readiness waiter. This
does not prove that identical wait activity occurred in the two public runs;
sample absence alone cannot demonstrate eliminated work.

The [baseline profile](https://github.com/redstone-md/mosh-flutter/actions/runs/40145525630)
did recover this caller, its `time.After`/`time.NewTimer` allocation path and
three readiness waiters in the service-only snapshot. Source inspection,
deterministic tests and the paired benchmark establish removal of periodic
polling. The public reprofile only supplies additional integration observations.

Baseline OS CPU was 0.671875/1.796875 seconds for the two phases; the candidate
goes in opposite directions across phases. Different hardware, public traffic,
topology, wait activity and sampling overhead prevent a causal CPU comparison.
Sampler weights also disagree with OS counters, including in the candidate.
Do not turn sample percentages into conserved CPU attribution or claim a
whole-application improvement from these profiles.

Allocations include profiling and network work. Cumulative pprof allocation
samples may lag GC and include preceding activity; they are not interval
retained memory. The probe excludes Flutter, Rust, database/history and the
owner's actual messages. No physical Android background/battery validation or
owner desktop acceptance is supplied here.

The artifact's 21 names, CRC, API digest, source/config fingerprints, room/read
counts and monotonic allocation/GC counters were verified. Configuration hash
comparison accounts explicitly for Windows CRLF conversion.
Artifact SHA-256:
`5a0d4410585f628ba78b6a73726e281ccbdae3b2b77f6aca4f1f4358ec273563`.

## Remaining acceptance

Keep Mosh's shipping pin at `979a634` until the stacked Moss changes are
reviewed and explicitly approved for integration. A subsequent matched Mosh
build must establish the desktop effect; Android background incoming calls,
battery and network use still need their own device checks. The event-driven
wait does not change other LAN/discovery/network maintenance paths.
