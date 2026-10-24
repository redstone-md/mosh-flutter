# Issue 94: owner callers and shared signature verification

The correction is `82cc774e`, following the
[scoped plan](issue-94-shared-verification.plan.md). Owner Windows CPU/network
acceptance and Android background-call/battery acceptance remain open.

## Owner evidence

The private input `callers-20261024-041744/mosh-callers-report.zip` has SHA-256
`db51ec8c63d1c1b66ef4c2164695b1c5455312f37b5cd8086ebf9d847fb2733e`.
Its PID, all five shipping hashes and 7,662 selected weights match the
[preceding CPU capture](issue-94-owner-cpu-20261024.results.md). No weights
are skipped. All 1,455 exported Moss leaf weights reconcile by exact DLL RVA
with the raw instruction capture. One weight lacks a recovered Go function
range and stays unresolved.

The export records trace SHA-256
`e5a9a6988c54d88d81373340d9b72d3d9470bdfafb3ede75bae64fdd43d61904`;
the raw ETL stays on the owner's computer, so it is not independently rehashed
here. No owner raw trace, full stack archive or endpoint addresses are published.

| Inclusive caller evidence | Weights | Share |
| --- | ---: | ---: |
| Windows adapter enumeration | 452 | 5.90% |
| Rust mesh snapshot | 365 | 4.76% |
| Strict Ed25519 verification | 341 | 4.45% |
| Local identity opening | 356 | 4.65% |
| Mark-viewed command | 242 | 3.16% |

Rows overlap. Roster verification contains 241 strict-verification weights;
DM identity claims contain 85. Actual caller paths show fresh identity loading
under deletion authority, lists and protocol service, and repeated claim
verification under DM topology validation. These distinguish the remaining
signature work from a shared curve leaf alone.

2,755 weights contain broken unwinds. Adapter paths lose the calling Go
goroutine at the system-stack transition. Flutter frames also lack useful
names. These samples neither explain all CPU nor justify changing interface,
rendering, discovery or polling cadence in this correction.

## Reproduced cause and correction

Fresh decoding resets each roster's per-object OnceLock. Ten unchanged
`DeviceIdentity::open` calls perform ten extra strict signature checks.
Ten decode/validate cycles of an unchanged two-user DM topology perform
eighty extra checks across roster and claim signatures. Both caller regressions
fail on the previous implementation and pass after correction, preserving
identical serialized data.

The existing deletion verifier's success-only cache now lives behind the
crate-private `signature_verification` boundary. Roster and DM proof callers
reuse it. One shared 4,096-entry FIFO bound covers signature and certificate
fact namespaces; entries retain fixed-size digests, not bodies or identities.
Signature fingerprints bind the fixed 32-byte key, 64-byte signature and full
signed input. Signature text is decoded before hashing; accepted hexadecimal
representations identify the same mathematical fact. Nothing is serialized.

Callers still validate canonical strong device keys, descriptors, signer
authority, roster chain state, removal history and current MLS membership.
New rosters are read and folded normally. No authorization or whole-identity
cache is introduced. Strict verification runs on misses; failures are never
remembered. No lock spans cryptographic work, so concurrent misses can verify
twice. Certificate caching retains its complete-certificate digest and tag.

Ordering and tie-breaking of returned messages are unchanged. No RNG or
floating-point calculation changes. The operation removed on a hit is the
same deterministic signature-verification function on the exact same inputs.
Eviction restores that operation. Public APIs, storage, dependencies and
Moss source remain unchanged.

## Controlled native release comparison

Twenty pairs alternate execution order across forty fresh release API workers.
Each restores the same fictional eight-DM fixture with one acknowledged text
per DM, warms once and performs 600 actual list calls. This is the existing
small-history fixture, not the later 800-message upper-bound fixture and not
the owner's data. The normal 500 ms DM service thread is observed in every
worker. Both variants load the same privately isolated Go library, verified
through process mappings; zero mesh peers are asserted throughout. Builds and
host tuning do not overlap measurement.

Before production source is `406547a7`; its added red-test counters are test-only
and absent from the integration worker's production dependency. After source
is `82cc774e`. Both use the committed fat-LTO, one-codegen-unit release profile,
Rust 1.96.0 and the same Linux 6.12.105 host. Process CPU counters have 10 ms
resolution. Statistics below are medians across twenty processes per variant;
call percentiles are computed within each 600-read process before taking that
median. Extreme-tail percentiles are not claimed.

| Per process, 600 reads | Before | After |
| --- | ---: | ---: |
| CPU median | 0.960 s | 0.720 s |
| CPU range | 0.930–1.060 s | 0.700–0.790 s |
| Total wall median | 1.125 s | 0.880 s |
| Per-call p50 median | 1.723 ms | 1.325 ms |
| Per-call p95 median | 1.945 ms | 1.512 ms |
| Per-call p99 median | 2.422 ms | 1.931 ms |

CPU decreases 25.0%, improving in all twenty pairs. All 24,000 returned lists
retain the exact full message/identity/permission golden SHA-256
`0df47e54aed4e7713b8e6348ff4ec5b55bda1467f8c7c6e8a1e46eaa0de6f4bd`.
This isolates native API cost; it does not predict a 25% whole-Windows CPU
reduction or measure public-network bandwidth savings.

## Verification and handoff

Final-source build, fourteen focused tests, formatting, diff checks and
all-target Clippy with warnings denied pass. The tests cover changed
key/signature/input, failed checks, weak/malformed keys, bounded eviction,
concurrent/nested checks, tampering, current revocation and history permissions.
LLVM reports 84/86 covered lines (97.67%) in the shared verifier; branch
coverage data is unavailable. Independent Standards and Spec reviews of the
immutable source tree both report zero actionable findings.

The final source's Windows and macOS core jobs each pass the full library
run (777 passed, 20 ignored), Clippy and their enabled integration targets.
Dedicated native workflows also pass real device linking, multi-device DMs
and audio/video on Linux, macOS and Windows. Flutter tests and bridge drift
checks, Windows native UI/installer and macOS menu/DMG checks pass in
[platform CI](https://github.com/redstone-md/mosh-flutter/actions/runs/40065223073)
(source `82cc774e`, attempt 2). The separate [configured Windows build](https://github.com/redstone-md/mosh-flutter/actions/runs/40065351610)
passes with the committed fat-LTO, one-codegen-unit release profile.
No merge or release is included.

The configured installer is `mosh-0.24.1-setup.exe` from source `82cc774e`,
[artifact 12549402945](https://github.com/redstone-md/mosh-flutter/actions/runs/40065351610/artifacts/12549402945).
Its SHA-256 is
`66cd82f271be08d756a456b8516097544f3cac474fd01dd01f580fc20917eca3`.
Both downloaded artifact ZIP digests match GitHub metadata. All five extracted
shipping binaries match the source manifest; the original Rust DLL and PDB
match their manifest hashes and CodeView GUID/age. The public PLUS manifest
confirms the mainnet billing origin and existing issuer pin. Original binaries
and matching symbols are retained privately for the next owner capture.

The all-page CodeAnt audit of Mosh #96 and Moss #29 finds no unresolved inline
findings or summary nitpicks. No exact-source CodeAnt review object is present;
this is not a claim of bot approval.

For owner acceptance, exit through the tray, install this EXE, reopen the same
profile/offline chat and allow ten minutes to settle. The existing
`Start-CPU.cmd` then records CPU and network for 90 seconds; send only its
`mosh-cpu-report.zip`. The earlier existing-trace exporter pins the old
`f9727ccf` build and must not be used to attribute this new executable.
