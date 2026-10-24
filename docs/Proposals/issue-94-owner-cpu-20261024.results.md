# Issue 94: owner Windows capture, 2026-10-24

This capture follows the [known-recipient discovery verification](issue-94-dm-discovery.results.md).
It shows lower observed idle traffic and CPU. Whole-owner acceptance remains
open; the original reported 100–150 Mbit/s source is not established by this
90-second observation.

## Evidence and identity

The private input is `cpu-20261024-031529/mosh-cpu-report.zip`, SHA-256
`2fca964658174f97512be182be248433311321348a61e8e747388c5f465f95f3`.
No raw owner trace or endpoint addresses are published here.

All five application hashes match the configured full-release installer from
[run 40053211809](https://github.com/redstone-md/mosh-flutter/actions/runs/40053211809):
Mosh `f9727ccf`, pinned Moss `979a634`. The original Rust PDB has the matching
DLL GUID/age and verified checksum recorded in the linked verification.

The capture lasts 90.483 seconds. Its ETW control passes, all three event/buffer
loss counters are zero, and endpoint, protocol and per-second totals reconcile.
The process has been running for 375.87 seconds at capture start. Its window
handle exists throughout; that does not establish foreground visibility.
The archive does not establish the current saved-chat inventory or applied
KnownPeers policy counts.

## Observed comparison

Both captures use the same reported Ryzen 7 6800H, 16 logical processors and
Windows 10.0.26200.0. The preceding capture is `cpu-20261023-233338`, using
Mosh `97a9851f` / Moss `82eb8b6`. Its process is 608.95 seconds old at capture
start. Public topology, process age and retained state are not controlled, so
the differences below are observed changes, not an isolated causal A/B.

| Metric | Previous capture | Current capture |
| --- | ---: | ---: |
| Mean external send + receive | 1.374 Mbit/s | 0.436 Mbit/s |
| Median complete second | 0.981 Mbit/s | 0.339 Mbit/s |
| p95 complete second | 3.936 Mbit/s | 0.984 Mbit/s |
| Peak complete second | 9.458 Mbit/s | 6.426 Mbit/s |
| Process CPU, one logical core | 14.478% | 10.318% |
| Median working set | 280.64 MiB | 133.18 MiB |

Mean external traffic is 68.2% lower and process CPU is 28.7% lower in this
observation. Current send/receive rates are 0.173/0.263 Mbit/s. No complete
second exceeds 10 Mbit/s. CPU equals 0.645% when normalized over this host's
16 logical processors; it comes from process CPU-time deltas, not profiler
sample counts. First-minute CPU is 10.76% of one core and the remaining
approximately 30 seconds average 9.47%.

## Remaining attribution

The 7,662 raw instruction weights reconcile exactly with the CPU summary.
All 1,261 Rust weights resolve against the original DLL/PDB; 1,454 of 1,455
Moss weights map to the attached Go function ranges. Weights are sampled
instruction observations, not CPU milliseconds or caller durations.

- Curve arithmetic appears in 506 weights (6.60% of all weights). This includes
  operations used for key derivation, signing and verification. Inline frames
  do not identify which application callers requested the work.
- Rust also contains serialization, allocation and bridge encoding work.
  Repeated identity/roster reads are candidates, not established owner causes.
- Moss contains allocation, garbage collection, JSON and mesh-info work;
  `MeshInfoJSON` itself has 38 flat weights. That count does not include its
  complete callees and does not establish its total cost.
- Flutter contributes 877 module weights. These do not identify a particular
  widget, polling loop or rendering trigger.

The independent shipping-Windows GUI caller control shows repeated identity
and topology paths, but its caller proportions cannot be assigned to the
owner's machine. The next discriminating evidence is selected-process caller
paths from this owner's existing `raw/cpu.etl`, using the same original PDB.
No new recording or application restart is required. An exporter must reject
other application builds and must not implicitly select an older report.

The owner has now supplied matching caller paths. The
[shared-verification follow-up](issue-94-shared-verification.results.md)
records the attributed repeated checks, caller regressions and matched native
comparison. Live membership and revocation checks remain independent of the
bounded successful-signature cache.
