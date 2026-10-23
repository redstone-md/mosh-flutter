# Issue 94: Windows interface enumeration

The owner's original trace proves adapter-enumeration cost, but its re-export
cannot identify the Go caller across a runtime stack switch. A separate
Windows probe attributes the candidate paths. The user authorized the narrow
Moss-source exception, and the shared implementation is now pinned by Mosh.
This investigation does not establish a cause for residual network traffic.

## Owner evidence

The October 23 RVA-preserving caller ZIP has SHA-256
`0b1ca8139a75db425655ff5984a908be6a05824d28196fa0adbcb5c3623d952b`.
Its identity equals the earlier caller export: PID 13364, runtime `cd6df31b`,
all five binary hashes and original trace SHA-256
`c79cb56a0a6187ed154866a9ef422012626837f0f49192075cebc5df6d887a46`.
The owner reported an open saved offline DM. The export does not establish
chat inventory. Process counters recorded 12.909% of one core;
the network window averaged 1.474 Mbit/s. This is not a new runtime capture.

The 5,716 paths conserve all 9,924 selected weights; 1,154 foreign weights are
excluded. `BROKEN` still occurs in 4,972 selected weights. The 680 distinct
Moss RVAs are looked up in the original binary's 11,326 Go 1.25.9 function
ranges. Bounds checks prevent attributing C glue or gaps to a nearby function.

All 921 inclusive `GetAdaptersAddresses` weights (9.28% of selected weights)
have the same available Go ancestry, leaf toward root:

```
GetAdaptersAddresses
runtime.asmstdcall
runtime.asmcgocall_landingpad
runtime.asmcgocall
BROKEN
```

These are CPU sample shares, not process-counter durations. The runtime
frames prove a Go-to-Windows call; they do not distinguish mesh queries,
address announcements or LAN discovery. Another export cannot recreate the
missing goroutine stack. No additional owner recording is required for this
investigation.

## Candidate paths and falsifiable checks

| Rank | Candidate | Evidence and prediction |
| --- | --- | --- |
| 1 | Mesh queries enumerate interface addresses repeatedly | `MeshInfoJSON` calls `advertisedListenAddr`; the fallback uses `net.Interfaces` and `Interface.Addrs`. A standalone query profile should contain these callers without starting a node. |
| 2 | Per-interface address reads multiply Windows enumeration | Go 1.25.9's Windows `interfaceTable` and `interfaceAddrTable` both call `adapterAddresses`. Enumerating eligible interfaces and their addresses should cost more than listing interfaces alone. |
| 3 | LAN discovery accounts for the adapter work | LAN broadcast preparation also reads interfaces and addresses. An isolated started node with LAN enabled should show that path; the LAN-disabled control should not. |

The first two can both be true. None of these source observations identifies
the fraction of the owner's 921 weights caused by a particular caller.

## Controlled probe

The measurement-only `scripts/perf/moss-profile` program on
`test/windows-idle-current` imports the pinned `eb79f38` Moss package through
a separate Go module. It adds no application dependency or public API and
does not edit Moss. The runner uses Go 1.25.9 and optimized default Go builds.

Independent fifteen-second scenarios profile interface listing, interface
listing plus up/non-loopback interface addresses, unstarted-node mesh queries,
and isolated started nodes with LAN disabled/enabled. Public trackers, DHT,
port mapping and telemetry are disabled; the private discovery network does
not join the public swarm. Each output records scenario, iteration count,
elapsed time, toolchain and interface counts. Go's own profiler retains
goroutine ancestry instead of relying on Windows native unwinding. Idle
controls sleep for the whole interval, without an artificial polling timer.
LAN activity must be established by actual LAN-loop/beacon frames; successful
node startup alone cannot establish it because LAN socket setup may fail.

[Windows run 39978352834](https://github.com/redstone-md/mosh-flutter/actions/runs/39978352834)
passes at measurement commit `7cc6b964`. The runner reports three interfaces,
two up/non-loopback. Moss's stricter production eligibility remains in effect
inside mesh-query; the generic address scenario intentionally uses the broader
up/non-loopback set. Validation occurs before profiling, outside the query loop.

| Busy component, separate 15 s intervals | Completed iterations | Inclusive adapter API share of Go CPU samples |
| --- | ---: | ---: |
| Interface list | 10,945 | 98.63% |
| List plus per-interface addresses | 3,448 | 97.81% |
| `MeshInfoJSON`, unstarted isolated node | 5,568 | 93.70% |

The query profile recovers two concrete chains through `advertisedListenAddr`
and `bestLocalAdvertiseHost`: one reaches `net.Interfaces`, the other reaches
`selectAdvertiseHostForInterfaces -> Interface.Addrs`. Both enter the same
Windows adapter API. Generic address enumeration makes one list query plus
one address query per selected interface; the source mechanism and component
profiles support the repeated-enumeration hypothesis.

The LAN-enabled profile contains actual `lanDiscoveryLoop -> sendLANBeacon`
frames (90 ms inclusive sampled weight), including advertised-address
construction, interface selection and broadcast address construction. This
establishes activity rather than relying on node-start success. LAN-disabled
has no LAN frames but still has 20 ms of adapter samples through
`maintenanceLoop -> connectBootstrapSeeds -> bootstrapSeedTargets -> advertisedListenAddr`.
Thus LAN is not the only background caller. All three candidate mechanisms
are observed in controlled profiles; their proportions in the owner's trace
remain unknown.

These are separate short component captures, not a statistical optimization
comparison, a matched owner workload or whole-application A/B. CPU model is
not recorded in the probe artifact; timings cannot be compared across hosts.
Go sampled weights are distinct from the owner's process CPU counters. The
probe does not measure or explain public-network bandwidth. The attribution probe itself made no production-source change.
The implementation and its matched result are recorded below; issue 94 remains open.


## Implemented boundary

Moss runtime `3526e05` supplies an operation-local interface inventory. It
introduces neither a Mosh polling delay nor a cross-operation TTL cache:

- Read Windows adapters and their addresses together once per inventory,
  only when the operation needs local interfaces;
  retain IPv4/IPv6, masks, anycast entries, interface indices, flags and order.
- Supply that inventory to local-address selection and LAN broadcast/interface
  selection so per-interface lookups do not repeat the full Windows query.
- Preserve address preferences, virtual/VPN-interface exclusions, selected-NIC
  binding, fallback/error behavior, discovery cadence, gossip fanout and retries.
- Refresh on every operation. No stale-network interval, persisted schema,
  public API or new library is needed; use Moss's existing Windows dependency.

This is shared implementation work with no Mosh-only option. The beacon
regression first failed with three inventory reads and two address reads; it
now passes with one of each. The next operation observes a changed address
in both payload and broadcast target. Selection, virtual/VPN exclusions,
local address failures, failed-inventory retries and fast paths are covered.
Windows tests compare exact ordered metadata/address values with the standard
library, including IPv4-mapped IPv6 masks, anycast, media flags, IPv6 index
fallback, owned memory and native buffer growth. Owner idle/network acceptance
remains separate.

Read-only consumer inspection at Bastion `39885d60` confirms that
[`mosslink.Status`](https://github.com/redstone-md/bastion/blob/39885d60a9175e15df3635ddb74b5807360ccd3f/server/internal/mosslink/mosslink.go#L382)
uses the public `MeshInfoJSON` method. Its
[`go.mod`](https://github.com/redstone-md/bastion/blob/39885d60a9175e15df3635ddb74b5807360ccd3f/server/go.mod)
replaces Moss with a vendored copy. The patch changes neither that public
method nor discovery/relay options. Direct substitution of Mosh's entire Moss
pin cannot compile Bastion: its existing vendor exposes four additional APIs
(`RelayAlways`, `PeerTransport`, `AddKnownPeer`, `PeerIDHex`). This predates the
interface patch. A disposable copy of Bastion's own vendor accepts the same
private inventory/beacon change with address-selection wiring adapted to its
older policy, without adding Mosh's routing preferences. The `mosslink` package
tests pass before and after that backport on Go 1.27.0. Bastion product source
and its repository are unchanged. This is a compilation/package compatibility
check, not an SSH end-to-end test.

Opportunity score for eliminating repeated enumeration is impact 3 × confidence
4 / effort 3 = 4. The confidence is in the repeated-call mechanism, not in
attributing all owner load to this candidate. The user granted the narrow
Moss-source exception on October 23. Public Go/C contracts, storage, wire
formats, dependencies, discovery cadence and retries are unchanged.


## Matched Windows result at the final runtime

[Run 39996690076](https://github.com/redstone-md/mosh-flutter/actions/runs/39996690076)
uses measurement source `8614622a`, before Moss `eb79f38` and after `3526e05`.
Both optimized Go 1.25.9 executables are built before measurement. Twenty
pairs alternate order on one AMD EPYC 7763 Windows Server 2025 VM (two cores,
four logical processors, build 26100, image 20261021.278.1). No build runs during
measurement. Each process warms twenty reads then performs 600 mesh queries
on an unstarted isolated node with the same private identity fixture. Every
read checks the full JSON SHA-256; no node joins a mesh or sends application
traffic. The fixture and keys are excluded from artifacts.

| Median of twenty processes per variant | Before | After |
| --- | ---: | ---: |
| Process CPU, kernel plus user | 640.625 ms | 367.188 ms |
| Wall time | 1,520.112 ms | 803.172 ms |
| Per-read p50 | 2.558 ms | 1.307 ms |
| Per-read p95 | 3.111 ms | 2.013 ms |
| Per-read p99 | 3.748 ms | 2.210 ms |

CPU drops in all twenty pairs; the ratio of medians improves **42.68%**.
Windows process counters have 100 ns units but the observed values have
15.625 ms granularity. The 600-read loop includes identical hash
validation overhead in both variants. Per-process p99 uses only 600 readings.
This is a component result, not the owner's whole-Mosh improvement.

The complete-response golden is
`1fdd94ea1c1ba385a0497e4fcdee61a23eff289688cd8f3cb7d856bd6db0ea3e`.
Before/after executable SHA-256 values are
`7c417ba4f2009df92600009db0e6c5b94924888f1b8ccbbe25d510727e1a2988` and
`9fe85864437e3673c1766546b43a83b69b36e5ccda7c15af57a3b13cee4cbfde`.

An earlier independent twenty-pair run on a Xeon 6973P-C VM measured 36.84%
lower median CPU at implementation `5679568`, before dead-helper cleanup.
Do not combine measurements across hosts or add these percentages to the
roster/key optimizations. The final run's separate 15-second profiles complete
5,363 before and 10,444 after queries; Go sample weights remain distinct from
process counters and are not a second CPU-counter comparison.

The Windows live-inventory/focused tests pass. Go statement coverage is 93.1%
for the Windows reader, 90.5% for the common snapshot and 85.7% for beacon
preparation; branch records are unavailable. Local full `go test ./...`,
focused race/vet and the Linux C-shared build pass. Independent Standards/Spec
review found only two obsolete private helpers, which were removed. Mosh
integration and configured installer checks follow the new pin; issue 94 and
owner whole-application/network acceptance remain open.

## Owner acceptance at `c1a61257`

The fresh `cpu-20261023-204618` ZIP has SHA-256
`2ed79ab655dd884f0e46734ed620449b54402a3f3820c81f4995cf3c3c70653f`.
All five binary hashes match the independently verified configured installer
from [run 39997458526](https://github.com/redstone-md/mosh-flutter/actions/runs/39997458526),
source `c1a61257`, Moss `3526e05`. This is a new capture, not another export of
the original ETL. Hardware remains Ryzen 7 6800H, sixteen logical processors,
Windows 10.0.26200.0. The collector does not establish saved-chat inventory.

The 90.814-second network window starts at 2026-10-23T20:46:43.7986395Z,
3,605.780 seconds after process startup. The 89 process samples span 89.526
seconds; counters are monotonic. Network controls and completeness pass, all
ETW loss counters are zero, and both per-second and endpoint byte sums agree.

| Whole-process observation | Earlier `cd6df31b` capture | Current `c1a61257` capture |
| --- | ---: | ---: |
| CPU, one logical core | 12.909% | 13.090% |
| CPU, normalized over sixteen logical processors | 0.807% | 0.818% |
| Working-set median | 190.55 MiB | 150.72 MiB |
| Combined external network mean | 1.474 Mbit/s | 1.456 Mbit/s |
| Complete-second median | 0.753 Mbit/s | 0.790 Mbit/s |
| Complete-second p95 | 3.323 Mbit/s | 9.641 Mbit/s |
| Complete-second peak | 24.434 Mbit/s | 12.143 Mbit/s |

Whole-process CPU and mean bandwidth show no meaningful improvement in these
observations. The smaller working set and lower peak are observations, not
causal patch effects: process ages differ (about sixteen versus sixty minutes),
public topology and history are uncontrolled, and these are single captures.
The component benchmark above remains a separate, matched result. Issue 94
and owner idle acceptance remain open.

Current external TX is 4,852,426 bytes and RX is 11,673,403 bytes. Three full
seconds exceed 10 Mbit/s; none reaches 100 Mbit/s. Subsecond peaks remain
unmeasured. The largest anonymized endpoint accounts for only 4.95% of bytes;
endpoint aliases do not establish the number or identity of connected peers.

### Remaining CPU attribution

Use the exact-PID instruction data, not the collector's separate module-name
classification. Both contain 10,430 weights, but some classifications differ.
The instruction buckets conserve that total:

| Bucket | Selected instruction weights | Share |
| --- | ---: | ---: |
| Moss | 3,483 | 33.39% |
| Kernel addresses | 2,806 | 26.90% |
| Rust | 1,269 | 12.17% |
| Unmapped user addresses | 1,228 | 11.77% |
| Flutter | 861 | 8.26% |

Other mapped libraries account for the remainder. The original matching Rust
DLL/PDB resolves all 1,269 Rust weights. Go ranges resolve 3,480 of 3,483 Moss
weights; bounds checks leave three outside function ranges unassigned. Go
Edwards25519 leaves account for 898 total-process instruction weights (8.61%),
versus 209 of 9,924 (2.11%) in the earlier capture. These are leaf sample
shares, not inclusive caller costs or process-counter durations.

Approximate alignment of 88 CPU-counter intervals with traffic buckets gives
correlation 0.719. Lowest/highest traffic quartiles have median 0.421/2.596
Mbit/s and 9.19/14.52% of one core. This assumes uniform traffic inside each
second and establishes association only. Kernel samples do not identify a
driver, and flat crypto samples do not prove redundant verification.

Ranked follow-up hypotheses are signed Moss control-envelope work, network-stack
work associated with incoming traffic, and polling/bridge/JSON work. Existing
complete Go caller profiling and a fresh Windows GUI/minimized fixture are
used to distinguish these paths before any further runtime optimization.

### Independent current-release checks

[Windows run 40022962529](https://github.com/redstone-md/mosh-flutter/actions/runs/40022962529)
passes at measurement commit `a7389c34`, installing the same `c1a61257` EXE
and matching all five shipped binary hashes. The old exporter keeps its
original installer defaults; only the current GUI profile selects the new
immutable installer/source/checksum. Five parser tests and the real Windows
CPU/network collector checks pass.

The disposable fixture establishes eight acknowledged offline DMs, two groups
and one channel. Before/after restoration inventories and message-body hashes
match; no invitations remain pending. The AMD EPYC 7763 runner has two cores
and four logical processors. After 480 seconds of GUI warmup, separate
ninety-second windows observe:

| Sequential current-runtime window | CPU, one core | External network mean |
| --- | ---: | ---: |
| Visible offline DM | 2.084% | 0.465 Mbit/s |
| Minimized window | 3.639% | 0.169 Mbit/s |

Both network controls pass with zero ETW loss and reconciled byte sums. Native
HWND checks confirm the intended visible/minimized state. These are sequential
public-mesh observations on different hardware from the owner. They do not
establish a causal effect of minimizing, quantify a patch improvement, or
reproduce the owner's hour-old process and 13.090% CPU. All 612/587 selected
Rust instruction weights resolve with the original matching DLL/PDB.

A separate current-Moss Go profile uses the existing fictional native fixture,
six-minute warmup and ninety-second sample window. Rust product source matches
the shipping source; only a private profiling overlay adds Go's own CPU sampler.
Recovered verification callers are
`handleKnownPeerEnvelope -> verifyPeerAnnouncementEnvelope` and
`handleKnownPeerEnvelope -> verifySupernodeStatusEnvelope`. The focused trace
contains only two ten-millisecond samples, so it establishes those callers
without reproducing or explaining the owner's larger crypto share.

A second private overlay observes the results of every original size-valid
Ed25519 verification without skipping or changing a check. Its real crypto
tests cover valid/repeated/changed signatures; the native fixture retains its
message golden. After six minutes of warmup, a ninety-second window records:

| Signed control-claim domain | Successful checks | Repeated identical successful inputs |
| --- | ---: | ---: |
| Peer announcement | 1,850 | 1,622 |
| Supernode status | 234 | 203 |

Thus 1,825 of 2,084 successful announcement/status checks repeat (87.57%). Six
invalid peer-announcement checks still execute. Across all observed domains,
2,092 valid checks minus 1,830 repeats equals 262 unique complete
public-key/signature/payload hashes. The private observer's 20,000-entry bound
is not reached; no raw inputs or identities are needed in the result. The
recorded native fixture has 17–18 neighbors and about 0.268 Mbit/s of mesh
carrier traffic in that window. Carrier bytes are not the owner's ETW network
counter and exclude other network paths.

This supports a bounded positive-verification memo as the next CPU candidate,
keyed by the complete public key, signed payload and signature. It must cache
only the cryptographic fact: peer trust, admissibility, address updates,
capabilities and forwarding decisions must still run on every envelope.
Changed or invalid signatures must retain their existing verification and
rejection behavior. Such a memo does not reduce incoming wire traffic. No
production crypto/announcement behavior has been changed by these probes;
the previously authorized Moss-source exception covered interface enumeration.

The user subsequently approved the memo. Its implementation, matched comparison
and remaining limits are recorded in the
[announcement verification follow-up](issue-94-announcement-verification.results.md).
