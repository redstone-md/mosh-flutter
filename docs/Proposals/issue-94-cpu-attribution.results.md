# Issue 94: exact-process CPU attribution

The `cpu-20261023-000926` owner capture is usable for process CPU, memory,
network and relative instruction attribution. Its separate CSV-derived module
table disagrees with its PID-filtered raw samples and must not be used to
apportion CPU. This follow-up fixes the collector, not application runtime.

## Owner observations

Archive SHA-256:
`02f510cb3ba649ea392f7dd70e237ab0a956ec7203031fa3671fdb23c720acde`.
All five binary hashes match the configured `cd6df31b` installer, including
the loaded-key correction. Moss remains `eb79f38`. Hardware is Ryzen 7 6800H,
sixteen logical processors, Windows 10.0.26200.0.

The 90.819-second network interval starts at 2026-10-23T00:09:53.1298718Z,
956 seconds after process startup. CPU counter samples span 89.447 seconds.
All 89 samples have their window flag set. Trace completeness and controls
pass, loss counts are zero, and endpoint and per-second byte sums reconcile.

| Whole-process observation | Value |
| --- | ---: |
| CPU, one logical core | 12.909% |
| CPU normalized over sixteen logical processors | 0.807% |
| Working-set median / range | 190.55 / 169.49–202.40 MiB |
| Combined network mean | 1.474 Mbit/s |
| Complete-second median / p95 / peak | 0.753 / 3.323 / 24.434 Mbit/s |
| External TX / RX | 4,757,276 / 11,977,057 bytes |

Two complete seconds exceed 10 Mbit/s; none reaches 100 Mbit/s. Subsecond
peaks remain unmeasured. Relative to the preceding younger owner process,
CPU and traffic are higher and median working set is lower. Public topology,
GUI/history state and warmup differ: those observations do not measure a
causal patch regression or prove either a memory leak or its correction.

Approximate alignment of 88 CPU-counter intervals with byte buckets gives
correlation 0.571. The lowest-traffic quartile has median 0.426 Mbit/s and
9.25% of one core; the highest has 1.958 Mbit/s and 13.85%. This assumes
uniform traffic within each second and establishes association, not causation
or a traffic-free baseline.

## Attribution correction

The original shipping DLL/PDB identity matches `cd6df31b`:
`{41B1E1DB-51C6-438F-866B-CCE6C024A86F}`, age one. All 1,429 raw Rust weights
resolve. Recovered Go ranges map 2,464 of 2,469 weights; five remain unmapped.

The CSV table has 11,078 weights and attributes only 673 to Moss. Exact-PID
instruction data has 9,924 total weights and attributes 2,469 to Moss. CSV
also names unrelated application modules. These exports cannot share a
denominator or be treated as an exact module budget. Raw samples retain
their PID filter and the selected process's actual loaded-module ranges.

Reconstructing only from those raw samples gives:

| Bucket | Weights | Share |
| --- | ---: | ---: |
| Kernel addresses | 2,852 | 28.74% |
| Moss | 2,469 | 24.88% |
| Rust | 1,429 | 14.40% |
| Flutter | 903 | 9.10% |
| Unmapped user addresses | 1,271 | 12.81% |

Other mapped libraries account for the remainder. Kernel addresses here are
one bucket, not a claim about an individual driver. Statistical sample
shares are separate from process CPU milliseconds.

Rust leaves include curve arithmetic, allocation, JSON formatting and bridge
byte encoding. Go leaves include memory copying, curve arithmetic, GC and
map/JSON work. `MeshInfoJSON` has 62 own instruction weights, about 0.62% of
the raw total; flat samples do not establish its inclusive cost or caller.
Neither repeated key construction nor every remaining curve operation can
be inferred from a shared arithmetic leaf. Existing matched key benchmarks
remain valid and are documented in the [loaded-key report](issue-94-identity-key.results.md).

## Collector defect and fix

The collector asks PerfView to select CPU CSV data by process name and
greatest CPU, while its instruction export selects the requested PID.
[PerfView v4.0.0 implements that name-based selection here](https://github.com/microsoft/perfview/blob/v4.0.0/src/PerfView/UserCommands.cs#L170).
With two matching names, a busier foreign process can therefore own the
summary. The precise cause of every discrepancy in this owner's CSV cannot
be recovered without the separate private raw trace; that stronger claim is
not made.

The fix derives the existing module-summary fields directly from the same
PID-filtered instruction aggregate. Mapped, kernel and unresolved weights
conserve the total exactly. Kernel-only and unmapped-only traces remain
valid, while empty captures fail. The redundant CSV export and CSV parser
are removed. `[kernel]` explicitly groups kernel addresses. ZIP file names,
JSON field names and privacy boundaries remain unchanged.

No Mosh/Moss runtime, schema, public bridge contract or dependency changes.
The installed application and the existing owner ZIP do not need replacement
to analyze these observations.

## Checks

The [RED live Windows run](https://github.com/redstone-md/mosh-flutter/actions/runs/39882109937)
fails the exact-PID conservation assertion with a busier same-name worker.
The first attempted green run exposes a PowerShell 5.1 limitation in a test
assertion over hashtables; selecting scalar weights corrects that assertion
without weakening it. A review also catches partial-startup cleanup, fixed
by placing both worker launches inside null-guarded cleanup protection.

The [corrected Windows diagnostics run](https://github.com/redstone-md/mosh-flutter/actions/runs/39882890263)
passes at `e16f2658`. Target CPU is 14,859 ms versus foreign worker 43,391 ms;
both selected-PID summary and raw data contain exactly 4,114 weights.
Focused tests cover foreign PID and non-IP exclusion, mapped/kernel/unknown
buckets, conservation and kernel-only/unmapped-only/empty input. Real UDP,
recording lifecycle, archive privacy and packaging checks also pass.
Formatting/diff checks pass. Independent Standards and Spec reviews of
`2b7a9766...e16f2658` have no remaining actionable findings.

The [verified collector bundle](https://github.com/redstone-md/mosh-flutter/actions/runs/39882890263/artifacts/12470374755)
contains all twelve expected shipping files from `e16f2658`; their contents
match source and the SHA-256 sidecar verifies. The ZIP SHA-256 is
`38c2cd31b1d453aa2683b5dbc969c2d84f8082405066c1278a20d8a74248296c`.
It is a diagnostics update, not another application installer.

All CodeAnt thread, review and general-comment pages have also been fetched.
There are no unresolved inline findings or published nitpicks for Mosh #96.
The latest recorded completed review is `ded4e691`; a completed CodeAnt
review of the subsequent collector correction is not yet recorded. Moss #29
remains at the reviewed `eb79f38` with no unresolved findings or nitpicks.

## Public-mesh caller profile

A separate Linux release process restores the existing fictional fixture:
eight acknowledged offline DMs, two groups and one channel. It uses the
`cd6df31b` native runtime and unchanged `eb79f38` Moss sources, with a private
Go compiler overlay that only adds delayed CPU profiling. No tracked Moss
file changes. Discovery is enabled, the ordinary background DM service runs,
and the fixture performs one-second names/list/open-DM reads. Group and
channel lists are each read twice per cycle, as in the preceding paced
experiment; this is not a claim that today's Flutter UI duplicates them.

After six minutes of warmup, a ninety-second profile holds fourteen mesh
peers. Process counters span 89.325 seconds at **3.806% of one core**. All
message fields still match the existing golden at every read, and group and
channel inventories remain intact. The actual loaded library and unchanged
Moss source pin are checked. Raw profiles, fixture identities and logs stay
private.

The Go shared-library profiler records 279 sample weights, or 2.79 sampled
CPU seconds. It includes native external work: `runtime._ExternalCode`
accounts for 33.69%. Its denominator is therefore not a Go-only CPU budget.

| Inclusive profile path | Sampled CPU seconds | Profile share |
| --- | ---: | ---: |
| Mesh-info FFI / `MeshInfoJSON` | 0.30 | 10.75% |
| LAN beacon and interface enumeration | 0.27 | 9.68% |
| Peer dispatch worker | 0.18 | 6.45% |
| Envelope handling | 0.12 | 4.30% |
| Envelope wire send | 0.12 | 4.30% |
| Ed25519 verification | 0.07 | 2.51% |

These paths overlap and must not be added. The profile identifies measurable
serialization, interface, network and cryptographic work, but no single
runaway caller. It is a small Linux sample with different hardware, topology
and message history from the Windows owner. Neither its absolute CPU nor
its relative shares quantify a Windows fix or a bandwidth reduction.

The current Flutter list provider serializes each kind's refresh and shares
that inventory among its consumers. The foreground poller refreshes those
three canonical lists, then the active conversation. Existing DM maintenance
and list reads already batch their per-session mesh observations. Source
inspection therefore does not justify claiming a new duplicate-poll defect
or adding a global TTL cache. Shared byte-encoder and curve-arithmetic leaves
also do not identify a caller to change safely.

The confirmed fix in this increment is exact-PID diagnostics. Actual residual
Windows CPU and public-mesh traffic remain unresolved; more caller evidence
is required before another runtime change. The subsequent
[full Windows GUI capture](issue-94-windows-callers.results.md) resolves useful
Rust callers but does not reproduce the owner's residual load. Whole-Windows
idle and Android background-call/battery acceptance stay open in issue 94.
No merge or release is included.
