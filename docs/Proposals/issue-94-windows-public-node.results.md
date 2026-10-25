# Issue 94: Windows Go caller attribution

The disposable Windows node recovers Go callers that the owner's ETW trace
could not unwind. Remaining LAN adapter enumeration comes from beacon sending,
and explicit offline-target attempts poll direct-connection state every 25 ms.
These are specific optimization candidates, not proof of the owner's entire
remaining CPU cost. No additional production networking change is made here.

## Identity and integrity

[Run 40145525630](https://github.com/redstone-md/mosh-flutter/actions/runs/40145525630)
passes on measurement source `02c7012520cf2b13abb4ceb62be8197a52c9cc59`.
The optimized standalone Go 1.25.9 executable imports unchanged shipping Moss
`979a63459e7327aec5a318b108d0382a8f5b091c`. Its SHA-256 is
`3c36143a5ece38484b73cd827ac1e080b9a9ca670f7f50cac7b7c82f661ad393`.
The [artifact](https://github.com/redstone-md/mosh-flutter/actions/runs/40145525630/artifacts/12581216690)
contains exactly twenty-one expected files and passes ZIP CRC and GitHub digest
verification. ZIP SHA-256:
`253fc07c83e932a3ff4525e33bf5687bfa53e9c969533dbb4c09adabf085800c`.

The runner reports AMD EPYC 7763, two cores/four logical processors, Windows
Server 2025 build 26100, image `20261021.278.1`. Committed configuration source
is byte-identical to `aa17f31e` with LF SHA-256
`751696aaf142bf44d06d3e31dca61f6c1400fda5c0b72064e6079263971b2e58`.
Its Windows checkout uses CRLF, independently reproduced SHA-256
`075669e4cec5296e10cd5ba1f30c216ed899b273741420b9a89a1a81a221bfcb`.
This explains the different recorded file hash without accepting different
configuration content. The probe excludes node logs, keys and endpoints.

## Scenario and counters

The [plan](issue-94-windows-public-node.plan.md) defines eight fictional offline
DM recipients using KnownPeers, two groups and a channel using Automatic, with
eleven rooms and thirty-three subscriptions. The node publishes no application
content. After eight minutes of warmup, the same process records separate
ninety-second phases with paced mesh reads and then background service alone.
Both phases begin and end with twelve direct peers, no relayed peers and no
active relay sessions/routes. Known peers change 412 → 413 → 414. NAT reports
`port_restricted_cone`.

| Process observation | Mesh reads | Service alone |
| --- | ---: | ---: |
| Elapsed counter window | 90.0005 s | 90.0005 s |
| Scheduled mesh queries | 539 | 0 |
| Process CPU counter | 0.671875 s | 1.796875 s |
| CPU, one logical core | 0.747% | 1.997% |
| CPU across four logical processors | 0.187% | 0.499% |
| Direct `TotalAlloc` counter delta | 69.09 MiB | 88.30 MiB |
| Completed GC cycles | 31 | 34 |
| `HeapAlloc`, before → after | 4.95 → 4.79 MiB | 5.12 → 4.58 MiB |
| Goroutines, before → after | 89 → 103 | 103 → 103 |

The background-only interval has higher measured CPU and allocation than the
query interval. Public traffic and time differ; this is not a controlled A/B,
an estimate of query removal savings or a direct comparison with the owner's
whole Mosh process. Neither window measures external bytes or working set.
The process counters include profiler overhead.

## Caller evidence

The CPU profiles contain 211/301 samples, expressed by pprof as 2.11/3.01 s.
Those sample totals do not conserve the 0.672/1.797 s OS process counters.
Use them to identify observed callers, not convert their percentages into
process CPU shares or predicted gains. Profile-writing work is also visible.
The ranked application paths below overlap; do not sum their inclusive weights.
Artifact filenames identify the exact evidence.

| Rank | Observed path | Mesh-read / service-only profile weights | Evidence |
| --- | --- | ---: | --- |
| 1 | Direct connection attempts, `tryDirectContext` | 170 / 250 ms | `node-*.cpu-top.txt`, CPU profiles |
| 2 | LAN beacon send, `sendLANBeacon` | 210 / 200 ms | `node-*.cpu-traces.txt` |
| 3 | Offline readiness polling, `waitForDirectPeerContext` | 170 / 150 ms | `node-*.cpu-traces.txt`, service goroutine profile |
| 4 | Peer dispatch | 30 / 190 ms | `node-*.cpu-top.txt` |
| 5 | Scheduled `MeshInfoJSON` | 20 / 0 ms | CPU profiles, JSON read counts |

Two adapter paths are recovered under `sendLANBeacon`: the existing local
inventory read in `prepareLANBeacon` and `ipv4.SetMulticastInterface` calling
`net.Interface.Addrs`. Service-only weights are 130/70 ms respectively.
They are not under a scheduled `MeshInfoJSON` query. This supports beacon-side
enumeration, not restoring a cache across changing network interfaces.

`waitForDirectPeerContext` stacks include `time.After`/`time.NewTimer` and
direct-peer map checks under `dialExplicitTarget`. Unchanged shipping
`node_holepunch.go` checks the predicate and allocates a new 25 ms wait timer
until success, cancellation or timeout. The final goroutine snapshot includes
three such waiters. This establishes periodic local polling during a pending
dial, not an unbounded dial rate or the original 100–150 Mbit/s cause.

## Allocation evidence and limits

`node-mesh-polls.alloc-top.txt` attributes approximately 36.85 MiB inclusive
sampled allocation to `MeshInfoJSON`, 53.2% of the 69.27 MiB profile difference.
Its 539 scheduled reads are confirmed independently. This is allocation churn,
not a CPU-dominance or retained-memory result. The service profile's 0.50 MiB
mesh-query allocation can come from the topology bookends and GC lag; zero
scheduled reads does not imply no query anywhere in those allocation snapshots.

The service allocation difference is approximately 85.47 MiB. Leading flat
producers include AEAD output buffers (16.01 MiB), UDP dispatch (7 MiB), topic
candidate ranking (6.50 MiB), UDP reads (6 MiB) and scramble sealing/opening
(4/3 MiB). The heap profile totals approximately 3.16 MiB at its completed-GC
view, including about 1.16 MiB attributed to the CPU sampler. It cannot establish
the owner's 226 MiB working-set ownership or absence of a leak.

Allocation profiles sample objects, can lag GC cycles and include profiler and
topology-query bookends outside the CPU interval. Direct `TotalAlloc` deltas
and these sampled profile differences have different scopes. No collection is
forced. The Go executable omits C-shared/FFI, Rust, Flutter and the owner's
network interfaces/store; it does not attribute their exact residual cost.

## Hypotheses and next boundary

- Supported: mesh queries create roster/JSON churn. They do not dominate this
  stand's CPU samples. Merely slowing UI refresh is not justified by this run.
- Supported: background LAN beacons enumerate adapters without scheduled reads.
  A blanket persistent adapter cache would risk route changes and is rejected.
- Supported: pending offline dials use repeated 25 ms readiness polling.
  An event-driven readiness wait is a concrete candidate for a scoped experiment.
- Not established: a retained-heap leak, the owner's entire remaining CPU cost,
  a new redundant signature check or reproduction of 100–150 Mbit/s.

The repository [scope rule](../../AGENTS.md) says:
“Do not modify `moss/` sources or sibling repositories.” This run changes none.
The next Moss-source experiment requires an explicit exception to that rule.
It would replace only private direct-peer readiness polling with notification
on state changes, retaining the same predicate, timeout and cancellation result.
There would be no public API, discovery policy, retry cadence, dependency or
wire-format change. This is a proposed experiment, not an implemented fix or a
claim of whole-Mosh savings.

Before shipping such a change: regress immediate readiness, relay-only state,
direct promotion, wake-before-wait races, removal, cancellation, deadline and
shutdown; run race checks; use controlled offline/direct fixtures for at least
twenty alternating full-release pairs; preserve golden connection outcomes.
Accept it only if polling disappears, measured cost improves beyond noise and
delivery/reconnection checks pass. Otherwise discard the experiment. Keep Moss
source changes in a separate authorized branch/PR and leave this PR unmerged.

## Verification

Go vet, optimized compilation against the asserted shipping pin, clean Moss
checks and all pprof exports pass on Windows. Artifact inventory, hashes,
configuration bytes, read counts, topology conservation and monotonic allocation/
GC counters pass independent intake checks. Parallel Standards and Spec reviews
of the measurement implementation have zero remaining findings after correcting
query pacing, allocation baselines and the explicit shipping checkout.

The [owner results](issue-94-owner-cpu-20261024-230853.results.md) remain the
whole-application observation. Issue 94 and physical Android acceptance stay
open. No new owner recording, merge or release is requested here.
