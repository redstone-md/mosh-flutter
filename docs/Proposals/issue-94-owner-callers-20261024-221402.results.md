# Issue 94: caller export of the October 24 receipt-maintenance capture

This is a successful re-export of the existing owner trace at runtime
`54135ec0`, before the snapshot-authority correction `aa17f31e`. It identifies
remaining CPU paths but cannot measure that correction or explain the owner's
higher working set. No further production optimization is justified by these
stacks alone. Desktop idle and physical Android acceptance remain open.

## Identity and conservation

The private input `callers-20261024-221402/mosh-callers-report.zip` has SHA-256
`fa33c30ca80609716de5efed70c3466778c21db06be640dc25e2a2b3449c8769`.
Both expected JSON files pass ZIP CRC checks. PID 26464, runtime source
`54135ec0532522ab6dc771371ad8e1e3f0796b22` and all five shipping binary hashes
match the [original CPU capture](issue-94-owner-cpu-20261024-194749.results.md)
and its configured installer. The reported original ETL SHA-256 is
`0b84b3ec76482ba3489a382a9951bbf01dfa0fbed5e6840c1a88d4219e3b8d79`;
the raw ETL is not supplied, so that hash is not independently recomputed.

The 6,053 selected-process paths sum to all 8,267 reported weights, equal to
the original instruction total. No skipped weight is reported. However,
4,089 weights (49.46%) contain `BROKEN`: total conservation does not establish
complete ancestry. Go RVAs are resolved only inside the original matching
DLL's function ranges; the original Rust DLL/PDB supplies Rust symbols.

The caller leaf buckets match the legacy module summary, including Moss
2,045 and unresolved user addresses 1,119. The raw instruction export instead
has Moss 2,049 and unresolved user addresses 1,103. These differences were
already recorded in the CPU report. Do not equate individual module/address
buckets merely because all exports have the same total. The caller results
below use their own conserved denominator of 8,267.

Looking beyond the leaf recovers OS/library work below visible module frames:

| Path contains a recorded module frame | Weights | Share |
| --- | ---: | ---: |
| Moss, including its Go runtime | 3,906 | 47.25% |
| Flutter | 2,590 | 31.33% |
| Rust core | 1,219 | 14.75% |

These sets overlap: 46 weights contain both Moss and Rust, and 30 contain both
Rust and Flutter. Another 628 weights contain none of these module frames.
Do not add the three inclusive rows. They describe observed ancestry, not
complete ownership attribution: 3,860 of the 3,906 Moss-frame weights contain
`BROKEN`.
Moss/Go paths are a substantial part of the remaining observed CPU, but the
missing application caller prevents selecting a safe source correction from
that module share alone.

## Observed caller paths

| Inclusive path | Selected weights | Share of caller total |
| --- | ---: | ---: |
| Windows `GetAdaptersAddresses` | 506 | 6.12% |
| `PrivateDmRuntime::tick` | 323 | 3.91% |
| DM list API | 250 | 3.02% |
| Private-group list API | 213 | 2.58% |
| DM session snapshot | 205 | 2.48% |
| `DeviceIdentity::open` | 198 | 2.40% |
| Ownership-proof construction | 137 | 1.66% |
| Roster public-key decoding/validation | 121 | 1.46% |
| Conversation `mark_viewed`, all observed kinds | 85 | 1.03% |
| Rust strict Ed25519 verification | 22 | 0.27% |
| Old per-message local deletion permission check | 15 | 0.18% |

These are statistical, overlapping inclusive weights, not call counts or
process CPU milliseconds. Nested rows must not be added. Compiler inlining
and incomplete unwinds limit absence claims and comparisons with other traces.

None of the observed identity-open paths contains `BROKEN`. Ownership-proof
construction accounts for 87 of their weights, and 114 occur below local
ownership identity loading. Curve arithmetic there includes key construction
and key decoding; a generic curve leaf is not proof of repeated signature
verification. The strict-verification paths observed here belong to authenticated
group-control handling. This trace provides no evidence to weaken or broaden
the existing cryptographic-fact cache.

No observed `PrivateDmRuntime::tick` path descends from `mark_viewed`.
That is consistent with the receipt-maintenance correction; sampling cannot
prove that an unobserved call is impossible. The separately observed tick,
inbound service, snapshot and proof-building work still executes through its
normal callers.

Every one of the 506 adapter-enumeration weights ends across the same broken
Go stack switch:

```
GetAdaptersAddresses
runtime.asmstdcall
runtime.asmcgocall_landingpad
runtime.asmcgocall
BROKEN
```

This establishes remaining Windows adapter-query CPU, without identifying
which Moss operation requests it. The 23 `MeshInfoJSON` weights are its own
observed instructions with broken ancestry, not its inclusive adapter cost.
The earlier [interface investigation](issue-94-windows-interfaces.results.md)
already corrected repeated reads within one operation. This trace alone
cannot justify a new cross-operation cache, changed discovery cadence or a
claim that mesh queries account for all adapter work.

Adapter samples occur on 17 observed thread IDs; none of those threads contains
a Rust frame elsewhere in this sample. Thread identity cannot reconstruct a
missing Go goroutine caller or prove whether a particular API initiated its
work. It does not supply the missing attribution to foreground chat polling.

Go GC scanning appears in 151 inclusive weights, also with broken ancestry.
It does not identify allocating callers, retained objects or a memory leak.
The original working-set measurement remains distinct from heap evidence.

## CPU and traffic within the original interval

The collector's 88 adjacent CPU-counter intervals share the network recorder's
stopwatch. Approximate byte alignment, assuming uniform traffic within each
one-second bucket, gives zero-lag Pearson correlation 0.554. The lowest and
highest traffic quartiles contain 22 intervals each: their median external
rates are 0.215 and 2.081 Mbit/s, with median CPU of 7.66% and 13.09% of one
core. Thus CPU and traffic vary together in this recording, while noticeable
CPU remains in its lower-traffic intervals. This association neither identifies
a producer nor separates network processing from other simultaneous work.

## Decision and next controlled check

1. Snapshot construction remains a candidate. The new snapshot-authority
   correction must be evaluated on its actual Windows executable; this old
   trace cannot supply its after measurement. Native matched results and
   unchanged output goldens are recorded in the
   [snapshot-authority result](issue-94-snapshot-authority.results.md).
2. Rendering can contribute separately. A new disposable Windows run captures
   both an open offline chat and a minimized window, retaining exact shipping
   hashes, HWND state, full inventory and all 800 acknowledged message bodies.
   Sequential public-mesh windows do not isolate a minimizing effect or a patch
   improvement; their caller paths can distinguish observed work.
3. Network/runtime processing remains separate. Broken adapter/GC stacks and
   process network totals do not establish a removable network producer.
   No further Moss-source, traffic-policy or persistent authorization-cache
   change is made from this evidence.

The measurement-only branch retargets only the GUI profile to the configured
`aa17f31e` installer. The existing-trace exporter keeps its original `54135ec0`
pins, so this trace can still be replayed with its matching DLL/PDB. Five parser
tests, workflow/pin validation and diff checks pass. No product source,
dependency, bridge contract, schema or stored user data changes in this step.

## Completed check of the new Windows release

[Run 40138776790](https://github.com/redstone-md/mosh-flutter/actions/runs/40138776790)
passes at measurement source `175d4565`, using the already built configured
`aa17f31e` installer from run 40133081747. This does not rebuild the application.
The downloaded 27-JSON profile artifact has SHA-256
`8d5447245e7217d084c0f3bb3bcc9777af1acd86d5bb6c07df89d885cd41ed18`;
its GitHub digest and ZIP CRCs pass. All five installed binary hashes match
the release's original symbol manifest. The immutable installer retains its
previously verified production PLUS configuration.

The real fixture establishes eight offline DMs with 100 acknowledged messages
each, two groups and one channel. Before/after inventory and all 800 bodies
retain golden SHA-256
`c21241d354aee8750eed51232ab487bed2121eb65d9aa7eae00d6d37f4160def`;
no invitations remain pending. The host is an AMD EPYC 7763 Windows VM with
four logical processors. The GUI warms for 480 seconds before separate
ninety-second visible/minimized measurements.

| New runtime observation | Visible offline chat | Minimized |
| --- | ---: | ---: |
| Process age at network capture start | 522.09 s | 753.21 s |
| CPU, one logical core | 10.563% | 8.975% |
| CPU across four logical processors | 2.641% | 2.244% |
| Mean external send + receive | 0.152 Mbit/s | 0.097 Mbit/s |
| Complete-second p95 | 0.223 Mbit/s | 0.200 Mbit/s |
| Complete-second peak | 3.967 Mbit/s | 0.259 Mbit/s |
| Median working set | 116.46 MiB | 114.02 MiB |
| Raw instruction / caller weights | 11,393 / 11,393 | 10,770 / 10,770 |
| Broken unwind weights | 1,610 | 1,459 |

Both network controls pass, all ETW loss counters are zero and exact protocol,
per-second and endpoint byte sums reconcile. Raw/module/caller totals agree,
with no skipped caller weight. Native HWND checks confirm visible/minimized
state before and after the matching intervals. Software rasterization is
observed in 26.79%/26.75% of inclusive sampled weights; it is not a measured
cause of CPU load on the owner's physical GPU.

The new caller profiles retain 656/667 inclusive DM-snapshot weights,
178/180 identity-open weights and 88/102 adapter-query weights. No Rust strict
Ed25519 verification frame is observed. These statistical paths describe the
new runtime; absence under sampling is not a guarantee of zero execution.

The earlier `54135ec0` Windows run observed 9.598%/11.015% one-core CPU with
the same upper-bound history shape. The visible value is higher now, and the
minimized value lower. These are different runner instances and sequential,
uncontrolled public topologies, not a matched CPU A/B or proof of a minimizing
effect. Whole-Windows CPU improvement is not established. Neither current
window reproduces the owner's 261.10 MiB median working set or the original
reported 100–150 Mbit/s.

The old owner ETL is fully processed. The remaining owner check is a fresh
ordinary `Start-CPU.cmd` recording on `aa17f31e`, after installation/restart and
warmup, with the same saved offline-chat scenario. The exporter for the old
ETL remains pinned to `54135ec0` and is not a recorder of this new build.
Issue 94 stays open; no merge or release is included.
