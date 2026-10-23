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
probe does not measure or explain public-network bandwidth. Production source
is unchanged in this investigation; issue 94 remains open.


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
