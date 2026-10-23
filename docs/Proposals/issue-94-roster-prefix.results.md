# Issue 94: owner caller trace and verified roster prefixes

The owner's original Windows trace identifies redundant roster hashing during
permission reads. Runtime commit `1cd6fccc` replaces that comparison with private
entry equality while retaining chain verification. Twenty matched release API
comparisons reduce median process CPU by 13.24%. This is a native workload
result, not whole-Windows idle or network acceptance.

## Owner evidence

The sanitized `callers-20261023-035305` ZIP has SHA-256
`69840cf3ac8978400d2621245313e1f2630191073d3a517dd3259227f0a05294`.
It matches all five original `cd6df31b` binaries and trace SHA-256
`c79cb56a0a6187ed154866a9ef422012626837f0f49192075cebc5df6d887a46`.
Its 5,269 exact-PID paths conserve 9,924 weights; another 1,154 foreign-process
weights are excluded. Their sum, 11,078, matches the old name-selected export.

`DeviceRoster::extends` occurs inclusively in 263 selected weights, including
213 in digest generation below it. Admission/revocation checks account for
122 of those digest weights. The caller repeatedly clones a roster prefix,
serializes it and hashes both sides just to compare immutable entries.

Other costs remain: `DeviceIdentity::open` has 328 inclusive weights;
`GetAdaptersAddresses` has 921 (9.28%), with unresolved `moss!?` ancestors.
Moss's advertised-address and LAN-discovery paths enumerate interfaces and
their addresses. The Windows Go implementation performs adapter enumeration
for both `net.Interfaces()` and each `Interface.Addrs()` call. The trace does
not distinguish those Go callers or prove which enumeration path dominates.
No Moss source or network policy is changed here.

The same trace's network window contains 16,734,333 non-loopback bytes over
108 anonymized protocol/endpoint rows. UDP contributes 14,831,855 bytes
(88.63%); the largest row accounts for 22.59%, the five largest for 31.63%.
The load is distributed rather than dominated by one endpoint. These aliases
do not identify peers or packet content, and non-loopback includes LAN and
multicast traffic; this distribution does not prove a gossip/discovery cause.

`BROKEN` occurs in 4,972 selected weights. Go/Flutter names and module mappings
remain incomplete: the caller export's 673 Moss-module weights differ from
the exact-instruction attribution's 2,469. Foreign-process filtering alone
does not explain that difference. Sample shares overlap and are not process
CPU durations or evidence of the cause of network traffic.

## Change and behavior proof

`Authorization` gains private `PartialEq/Eq`; `extends` calls the existing
`self.devices()?` before `self.entries.starts_with(&base.entries)`. Every
serialized entry field participates, including exact strings and signatures.
The chain, ordering and error precedence remain unchanged; shorter chains and
forks still fail. The existing protocol digest and signed-parent verification
remain unchanged. No cache, public API, wire/storage format or dependency is
introduced. Floating-point behavior and randomness are unaffected.

The admission/revocation regression first failed with 40 digest calls instead
of zero. It now passes with zero. Differential tests compare all 25 ordered
pairs of genesis, linked, forked, removed and re-added rosters with the legacy
implementation. Malformed/empty current chains still fail before comparison;
revoked or re-added devices cannot reuse an old admission.

Existing native workers also restore the same fictional encrypted stores and
produce identical signed protocol packets and serialized roster values:

| Fixture | Entries | Signed packet SHA-256 | Serialized roster SHA-256 |
| --- | ---: | --- | --- |
| Original installation | 1 | `b7d68149b9ab26689c7756bcd806ff24d43569d1902e41eea75a8abb67b273ba` | `4bde8bc2f2183b18eb907e7ff082ad1f6812abc11443161a7f2cb0adc2017050` |
| Linked installation | 2 | `fb85bee90aa8670f450c4643924046d555f97985540b2ffbde08b51e24dce1f8` | `1e2f812de4dfec0efa09eb9a879137b869fc6ecea82a51d26d983952b914e202` |

Both revisions use the same fixture identity and signing inputs. Raw stores,
keys, packets, traces and unfiltered logs remain private.

## Matched release measurements

The committed fat-LTO release profile builds both native workers. The before
worker is the saved `cd6df31b` binary from the previous matched experiment;
only this roster comparison changes production source between revisions.
Their SHA-256 values are:

- Before: `829d250140cad92a5561f038802bbee820328cf2fdea0283800ad455e3fcae75`.
- After: `ee6f91fd44fd7186772fe84b09fe9ebc13d371cb6e9086f9a1dc3fc0ef4979a3`.

Twenty pairs alternate execution order on the same AMD EPYC 7713 Linux host.
Each process restores the same eight acknowledged offline DMs and performs
600 busy public native API list reads. The ordinary `mosh-dm-service` thread
is present; the manual-service flag is absent. No compilation or other test
suite runs during measurement. CPU counters have 10 ms resolution.

Both variants load the same existing discovery-disabled test Go library,
SHA-256 `5837aab91d7a2b2032c7bc7cba71bf0914a176b0cc4c178dc36d2631a6d2d5bd`;
the actual mapped library and zero connected peers are checked. This isolates
native polling work; it measures neither public-mesh traffic nor Windows GUI
idle behavior. The full message/identity/permission golden remains
`0df47e54aed4e7713b8e6348ff4ec5b55bda1467f8c7c6e8a1e46eaa0de6f4bd`
on every read in all forty processes.

| Median across twenty processes per variant | Before | After |
| --- | ---: | ---: |
| Process CPU for 600 reads | 1.095 s | 0.950 s |
| Process CPU range | 1.05–1.14 s | 0.92–1.01 s |
| Wall time | 1.229 s | 1.094 s |
| Per-read p50 | 1.902 ms | 1.671 ms |
| Per-read p95 | 2.253 ms | 1.961 ms |
| Per-read p99 | 2.491 ms | 2.103 ms |

CPU is lower in all twenty matched pairs; the ratio of CPU medians improves
by 13.24%. Do not add this percentage to previous optimizations or apply it
to the owner's 12.909% one-core CPU observation.

A separate Linux CPU-clock profile at 199 Hz exercises 6,000 reads per
variant. It records 2,102 before samples and 1,787 after samples; digest
generation below `extends` appears in 274 before samples and zero after.
Other digest calls remain, as required by the protocol. These profiles use
native symbol names without inline expansion and support the removed-call
claim; their sample counts are not the paired CPU-counter measurement above.

## Verification and next evidence

Local build, format, Clippy with warnings denied, three focused regressions
and the full library suite pass: 766 passed, 20 worker-entry tests ignored.
LLVM coverage reports 1/1 changed executable production line and 67/67 test
lines covered, excluding the test-only digest counter; branch records are
unavailable. Independent Standards and Spec
reviews find no actionable runtime issue.

[Application CI at `1cd6fccc`](https://github.com/redstone-md/mosh-flutter/actions/runs/39900175625)
passes all thirteen active jobs: Windows/macOS Rust, real DM/device-link flows,
Flutter, bridge drift, Windows integration, Android debug, native calls on
three desktop platforms and desktop packaging.
The separate configured installer is still compiling at publication in
[run 39901883481](https://github.com/redstone-md/mosh-flutter/actions/runs/39901883481).
Its workflow uses the committed release profile and preserves matching native
symbols; artifact checksums, configuration and DLL/PDB identity must be checked
before delivering that installer.

The diagnostic launcher defects are separate: the CMD entry scopes a clean
Windows PowerShell module path, preserves its exit code and removes the
download mark only from the bundled helper. The
[Windows regression at `69d5717f`](https://github.com/redstone-md/mosh-flutter/actions/runs/39901808537)
passes through the actual CMD entry with PowerShell 7 module paths and a
blocked helper, checks unchanged helper content and original ETL, and
conserves the selected PID's weights in the two-JSON report. These tools
remain on the auxiliary `test/windows-idle-current` branch.

Issue 94, residual Moss/interface costs, public-network behavior and Android
background-call/battery acceptance remain open. The next owner comparison
must record the new installer's hashes and the same idle workload. No new
owner recording is needed to retain or interpret this original trace.
Rollback of this runtime change is `git revert 1cd6fccc`. No merge or release
is included.
