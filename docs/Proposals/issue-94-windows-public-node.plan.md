# Issue 94: attribute remaining Windows Go work

The new owner capture matches all five `aa17f31e` release binaries. Its CPU
counter records 10.463% of one core / 0.654% across sixteen logical processors;
mean external traffic is 0.452 Mbit/s after excluding 486 pre-window bytes.
These are uncontrolled observations, not a causal before/after result. The
prior matching caller trace contains Moss/Go frames in 47.25% of selected
weights, mostly with broken native ancestry. Another export cannot reconstruct
a missing Go goroutine stack.

## Independent feedback loop

Extend the existing measurement-only Go probe on `test/windows-idle-current`.
Import the exact pinned, unchanged Moss module. Parse the same static network
overrides as `mosh-core/src/moss_ffi/config.rs`; record the configuration source
hash and the Moss/toolchain pins. Construct one disposable node in Mosh's
substrate room with eight fictional offline DM recipients, two groups and a
channel, each with three subscriptions. Use KnownPeers for the eight complete
fictional recipient sets and Automatic for the other rooms. Publish no content.
The probe checks out shipping Moss `979a634` explicitly in an ignored build
directory. The older measurement branch keeps its original submodule pin for
historical interface comparisons; it does not select this probe's dependency.

After 480 seconds of warmup, use Go's own CPU profiler for separate ninety-second
windows with six paced mesh reads per second and then background service alone.
Record process CPU counters, actual mesh-read counts, aggregate topology and Go
memory counters. Export CPU/heap/goroutine allocation stacks and aggregate JSON;
exclude keys, endpoints, raw mesh JSON, packet contents and node logs.
Allocation snapshots bracket each phase and `pprof -base` provides the
difference; Go memory profiles can lag completed GC cycles. No collection is
forced. Memory counters bracket the scheduled work inside the CPU sampler;
sampling overhead remains included. Heap snapshots describe the last completed
GC, not an exact ninety-second retained-object or leak measurement. Allocation
profile differences can include topology-query/profiler bookends outside the
CPU interval and GC lag; they are not exact interval allocation accounting.

The probe is an optimized standalone Go executable, not the shipping C-shared
library, Rust/Flutter application or owner's store. It can recover Go callers
on this stand; it cannot reproduce every cross-language scheduling cost,
attribute the owner's exact sample shares or validate all owner route-policy
opt-ins. Public topology can change between windows. No patch gain is inferred
from these sequential profiles.

## Ranked hypotheses

1. Paced mesh queries produce adapter enumeration and JSON/roster allocation.
   Prediction: the query window recovers these callers below `MeshInfoJSON`,
   and the service-only window has no scheduled query calls.
2. Discovery, maintenance and LAN beacons produce substantial work independently
   of UI reads. Prediction: the background profile retains these callers after
   scheduled reads stop, with topology and query counts recorded separately.
3. GC/retained allocation contributes. Prediction: heap allocation stacks and
   interval allocation/GC counters identify a producer; a GC CPU leaf alone is
   insufficient to establish retained objects or a leak.

Select a runtime change only after this feedback loop identifies a removable
cost. Any Moss-source implementation remains subject to the repository's scope
rule; this probe edits no Moss source. No timer, wire/storage format, dependency,
public contract or production permission decision changes.

## Checks

Verify the probe compiles against the pinned module, formatting/vet, successful
node and room/policy registration, read counts and nonzero public-peer discovery.
Fingerprint configuration, toolchain, source and hardware. Validate the produced
profiles with `go tool pprof` and preserve totals/sample limits. Independently
fix the reproduced pre-window collector defect with a failing Windows boundary
test followed by the same passing regression and real ETW collector checks.
Issue 94 and physical Android acceptance remain open.

## Results

The [completed Windows run](issue-94-windows-public-node.results.md) passes
the shipping-pin and artifact checks. It recovers LAN adapter and direct-peer
polling callers. OS CPU counters and sampler totals differ substantially, so
the result separates process utilization from stack weights. Further Moss
source changes require the explicit scope exception described in the results.
