# Issue 94: reuse a loaded installation key

Whole-Windows idle acceptance remains open. This follow-up removes repeated
Ed25519 public-key construction within one already loaded Mosh identity. It
changes no Moss source, discovery policy, timer, public API, wire format,
dependency or stored schema.

## Exact-binary owner capture

The owner supplied `cpu-20261022-213459/mosh-cpu-report.zip`, SHA-256
`47e060e265bc0172c11cba044e9621c0911e153bc9cea325727c1277119b733e`.
All five shipping binary hashes match the configured `a640f75a` installer
from run 39848146470. Moss remains at `eb79f38`. The 90.536-second interval
starts at 2026-10-22T21:35:21.6346213Z. Hardware remains Ryzen 7 6800H with
sixteen logical processors and Windows 10.0.26200.0. Capture completeness and
control checks pass, all trace loss counts are zero, and per-second and
endpoint byte totals reconcile. CPU counter observations span 89.194 seconds
within that network interval; all 89 process samples have their window flag set.

| Whole-process observation | Value |
| --- | ---: |
| CPU, one logical core | 9.214% |
| CPU normalized over sixteen logical processors | 0.576% |
| Working-set median | 269.82 MiB |
| External TX / RX | 2,229,614 / 3,362,900 bytes |
| Combined network mean | 0.494 Mbit/s |
| Complete-second median / p95 / peak | 0.346 / 1.842 / 4.101 Mbit/s |

The process is only 196 seconds old at interval start, versus approximately
twenty-nine minutes in the previous capture. Public mesh, traffic, GUI/history
state and warmup differ. The lower CPU/network and higher working set are
observations, not causal patch percentages or proof of a memory leak. The
process samples contain working set, not private-byte or heap attribution. The
previous owner's mesh-count snapshot does not describe this new interval.
No complete-second bucket reaches the reported 100–150 Mbit/s rate; these
aggregates do not measure subsecond peaks.

## Attribution

The original shipping DLL/PDB CodeView GUID is
`{60BA9EA1-9FAA-49AC-986F-DD36BA8E52D6}`, age one. All 1,794 Rust instruction
weights resolve. Of 9,521 CSV weights, Rust accounts for 18.84%, Moss for
16.27%, the principal kernel module for 20.86% and Flutter for 10.27%.
Raw instruction/kernel/unmapped totals are 9,520: one weight differs between
exports. Rust totals agree exactly; do not claim complete cross-export
reconciliation. Recovered Go ranges resolve 1,568 of 1,569 raw Go instruction
weights, with one unmapped. These statistical weights are not CPU milliseconds.

Curve arithmetic, JSON formatting and allocation lead Rust leaf rankings.
Identity loading, roster digests and ownership checks appear in recovered
inlined frames. Go `MeshInfoJSON` has 46 own instruction weights, approximately
0.48% of the CSV total; this does not establish its inclusive cost. Flat
instruction profiles cannot attribute every shared curve operation to a caller.

The existing release caller profile at the exact `a640f75a` runtime restores
eight acknowledged offline DMs, two groups and one channel. It identifies
`DeviceIdentity::open` and nested public-key construction under ownership proofs.
The same private compiler overlay disables public discovery; it does not edit
Moss source. Both API workers retain their normal background DM service.

## Reproduced cause and correction

`DeviceIdentity::key()` reconstructs a Dalek signing key from its seed on every
call. Dalek 2.2.0 computes the public key during `SigningKey::from_bytes`; its
ordinary `Clone` preserves that result. One account ownership proof constructs
the same key three times: validation, certificate construction and signing.
The caller regression performs ten actual proofs and observes thirty
constructions before correction, versus the ten necessary for ten separately
loaded identities. Repeated getters on one identity similarly observe eleven
constructions instead of one.

Commit `cd6df31b` retains one normal Dalek `SigningKey` inside each existing
`DeviceIdentity` owner. Its getter checks the current record seed before
cloning. Direct uncommitted seed edits derive a fresh key; a successful
persistence CAS aligns the retained key with the new record. Reload installs
the key from a freshly opened and fully validated identity. Failed writes or
validation do not install a new retained key.

Every persisted-row read, roster/certificate validation, expected-peer check
and current revocation check remains in place. This is not an authorization
or identity-validation cache. The bounded seed copy and public key share the
existing seed owner's lifetime and Dalek's enabled zeroizing secret-key Drop.
They are neither serialized nor exposed through an API. Direct dirty-record
edits intentionally keep deriving until update or reload aligns the owner.

Seven focused tests exercise actual byte-identical ownership proofs and
signature verification, repeated getters, direct edits, committed replacement,
stale-owner reload, invalid persisted seeds and revocation after warming.

## Matched release comparison

Twenty pairs alternate before/after order, restoring the identical encrypted
fixture before each of forty fresh processes. Each process warms once and
performs 300 real list API calls. Both variants load the same private isolated
Go library, verified in `/proc`; all eight messages are acknowledged and zero
mesh peers are asserted throughout. The public API worker retains its normal
500 ms background DM service. No heavy compilation or host tuning occurs
during timing. Before source is `a640f75a`; after source is `cd6df31b`.

| Per-process measurement for 300 reads | Before | After |
| --- | ---: | ---: |
| Median CPU | 0.710 s | 0.560 s |
| CPU range | 0.690–0.770 s | 0.530–0.640 s |
| Median total wall time | 0.786 s | 0.638 s |
| Median of per-process median call times | 2.448 ms | 1.948 ms |
| Median of per-process p95 call times | 2.669 ms | 2.461 ms |

Median CPU decreases **21.13%**, improving in every pair. The ten-millisecond
CPU counter resolution is small relative to each measured interval. Every
returned message field, including content, origin, identity and permission
metadata, matches the existing golden at every measured read:
`0df47e54aed4e7713b8e6348ff4ec5b55bda1467f8c7c6e8a1e46eaa0de6f4bd`.
This isolates native API work; it is not rendered Windows idle or public
network acceptance. Fixture keys and raw owner/profiling data remain private.

A twenty-second after caller profile records 3,520 samples and zero lost
samples. It completes 10,097 busy-list polls, versus the existing before
profile's 8,054. Ownership proof creation has 37.22% inclusive sampled work
versus 44.52%; identity loading has 46.85% versus 39.68%. These are nested,
relative shares of different throughput and must neither be summed nor
treated as absolute regressions. Current roster signature verification remains
a leading part of identity loading. Kernel symbol maps are restricted in this
profiling environment; unresolved kernel samples remain a limitation.

### Paced open-chat check

Three further pairs restore the same fixture, with both variants active at
once and alternating construction and poll order. Each warms for thirty
seconds, then measures ninety seconds. Every second each calls personal
names, DM list, group/channel lists twice and the selected offline DM poll.
The normal `mosh-dm-service` thread is observed in every process; the manual
service environment flag is absent. All DM message digests, two-group and
one-channel inventories and zero mesh counts are checked throughout.

Median CPU is **1.722% → 1.600% of one core**, a 0.122 percentage-point / 7.10%
relative reduction. Before ranges 1.711–1.756%; after ranges 1.578–1.622%.
Every pair improves. Only three pairs are measured, with public discovery
disabled equally in both variants. This supports savings with background
service and paced polling, without predicting Windows public-network CPU or
measuring bandwidth savings.

## Verification status

The construction-count regressions fail before correction and pass after it.
All 763 unit tests pass with twenty expected ignored workers. All-target
Clippy with warnings denied, formatting and diff checks pass. Focused LLVM
coverage maps all thirteen changed executable production lines, all 128 new
test lines and four test-only counter lines in the production module. Branch
records are unavailable. Independent Standards and Spec reviews of
`e17c9d64...cd6df31b` find no actionable issues.
CodeAnt completes its incremental `cd6df31b` review without unresolved inline
findings or nitpicks; all thread, review and general-comment pages are checked.

The complete [application CI at `cd6df31b`](https://github.com/redstone-md/mosh-flutter/actions/runs/39861130137)
passes all thirteen active jobs: both Rust lanes, Flutter, codegen drift,
real multi-device DM and linking, native audio/video on all three desktop
platforms, Windows bridge UI, Android arm64 debug and Windows/macOS packaging.
Android release is intentionally skipped on PRs. The separate Windows
diagnostics workflow also passes. Subsequent reporting changes only add these
measurements and links.

## Configured Windows installer

The [configured Windows EXE](https://github.com/redstone-md/mosh-flutter/actions/runs/39861533400/artifacts/12463383210)
is built from `cd6df31b` with the committed release profile. The proof-only
parallel-codegen step is verified skipped. Source/Moss pins, PE header,
SHA-256 sidecar and production PLUS manifest checks pass. The setup file is
55,803,537 bytes with SHA-256
`fac58b500aa947bf879b3af6c5601e9d12f43996cf4682474a22f37930b732fb`.
All five extracted shipping binaries match the co-produced symbols manifest.
The original Rust DLL/PDB CodeView GUID is
`{41B1E1DB-51C6-438F-866B-CCE6C024A86F}`, age one. The PDB hash and debug identity
match; the original PDB is retained privately for subsequent owner captures.

Moss stays at `eb79f38`. Its Go 1.25.9 DLL embeds parent Mosh revision
`cd6df31b` and therefore changes hash on this rebuild. The embedded revision
is not the Moss gitlink, which is checked independently. This is not a
one-binary Windows comparison.

Residual public mesh work, full snapshot serialization, retained-memory
behavior and Android background-call/battery acceptance remain separate.
The new configured Windows runtime still needs an owner idle capture after
warmup. Issue 94 stays open. No merge or release is included.
