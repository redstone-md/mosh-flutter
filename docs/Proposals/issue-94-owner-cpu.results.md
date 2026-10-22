# Issue 94: owner CPU attribution and repeated history verification

Windows idle acceptance remains open. This increment addresses repeated pure
signature verification in Mosh history snapshots. It makes no Moss policy,
protocol, storage, dependency or public bridge change.

## Owner capture

The owner supplied `cpu-20261022-132801/mosh-cpu-report.zip`, SHA-256
`c98c2a18a582672f40e60ea8e740ca6053d6f1efb228f5837ed61b5e070d372a`.
All five binary hashes match the configured installer from run 39692467913:
Mosh source `3e6790f5`, Moss `eb79f38`. The process is approximately sixteen
minutes old at capture start. Hardware: AMD Ryzen 7 6800H, sixteen logical
processors; Windows 10.0.26200.0. The 90.593-second network capture is complete,
control-validated and has zero event/buffer loss.

| Observation | Value |
| --- | ---: |
| Process CPU, one logical core | 14.148% |
| CPU normalized over sixteen logical processors | 0.884% |
| Working-set median | 239.54 MiB |
| Combined network mean | 1.853 Mbit/s |
| Complete-second median / p95 / peak | 0.714 / 7.379 / 26.211 Mbit/s |
| Receive share / UDP share | 71.59% / 94.30% |
| Statistical Rust / Moss / Flutter weights | 26.68% / 25.72% / 7.65% |

Instruction totals reconcile exactly with the module export: 12,332 samples.
All 3,172 Moss instructions match function ranges recovered from the shipping
Go 1.25.9 DLL. Edwards25519 multiplication/squaring and related curve work lead
its flat profile; mesh-info serialization and allocation also contribute.
These are instruction proportions, not per-module CPU milliseconds. This ZIP
contains aggregate instruction offsets, not full caller stacks. It does not
establish which caller caused every owner-side crypto check.

Approximate CPU/network interval correlation is 0.745, using overlap with
one-second byte buckets. This supports inspecting background network work,
but is not causal attribution. The reported 100–150 Mbit/s idle condition is
not present in this complete capture.

## Reproduction and ranked hypotheses

1. History-sized repeated verification: adding signed history increases CPU in
   unchanged UI snapshots, with stacks through `message_deletion`.
2. Public peer exchange: Moss signature work scales with incoming announcements.
3. Shared mesh snapshots: repeated JSON construction/decoding scales with the
   public peer directory and number of API polls.

A private same-binary Linux release probe restores the existing fictional
8-DM/2-group/1-channel fixture. It adds locally admitted, signed messages to one
offline DM, then issues thirty public `list_sessions` calls. The manual DM
service setting removes background DM timer variance; Moss still runs. This
isolates history cost and is not a whole-Windows or network acceptance test.

| Additional history | CPU for thirty calls | Median wall time per call |
| --- | ---: | ---: |
| 0 messages | 0.13 s | 4.17 ms |
| 100 messages | 0.85 s | 45.22 ms |
| 200 messages | 1.40 s | 63.48 ms |

A twenty-second sampled run on the 200-message fixture records no lost samples.
Callers lead from `list_sessions` / `snapshot_with_mesh` into
`MessageOrigin::verify_signature`, account-proof verification and
`DeletionAuthority::member_with_proof`. Curve arithmetic leads the flat profile.
This reproduces a history-dependent CPU cause; it does not prove all owner CPU
or the residual incoming bandwidth has this cause.

## Scope and invariants

The opportunity scores impact 4 × confidence 5 / effort 2 = 10. A bounded,
process-local cache retains at most 4,096 SHA-256 fingerprints of successful
cryptographic checks. Signature fingerprints cover the decoded public key, the
explicit signature-string length, the signature and the entire signed input.
The linked-history follow-up below adds a separate typed fact for a complete
serialized account certificate. No message bodies, keys, permission results or
serialized cache state are retained.

Strict verification, including weak-key rejection, still runs on a miss. Failed
checks never populate the cache. The cache lock is released before curve work;
concurrent misses may verify twice. FIFO eviction only causes re-verification.

Current membership, role, revocation, context and content checks stay outside
the cache. A cached signature cannot grant a permission after the corresponding
role/device is removed. No operation is suppressed or reordered, no RNG inputs
change, and output metadata must remain identical for unchanged authority.

The cache is an acceleration with bounded memory. Histories exceeding its working
set may still require repeated checks; full-history polling/serialization and
public network work remain independent costs. Rollback is one code commit.

## Verification

The caller-level regression first fails on repeated cryptographic work while
unchanged metadata remains correct. Independent snapshot checks reject altered
conversation/id/content-hash/author/signature/ownership transcripts and enforce
current role loss, membership removal and device revocation. The fixed focused
message-deletion suite passes all thirty-two tests, including existing linked
account, historical deletion and revoked-issuer scenarios. A cache bound check
covers eviction and duplicate admission.

`cargo build`, all-target Clippy, formatting and the full real-tracker
`node scripts/moss-test.mjs` run pass. The unit result is 749 passed / twenty
expected ignored workers; integration targets and doc tests also complete with
zero failures. LLVM coverage maps forty of forty-one production lines in the
new verification module (97.56%); its full module including the bound test maps
58/59 lines (98.31%). Branch data is unavailable.

Independent Standards and Spec reviews of `8fe80d00...8aa8bb65` report zero
remaining findings. CodeAnt finishes the `8aa8bb65` incremental review with no
unresolved inline findings or nitpicks. At `8aa8bb65`, linked account-certificate
delegation checks remain outside this helper/cache and its regression counter.
The following follow-up addresses that gap within history account proofs;
identity/roster validation remains separate.

## Release mechanism comparison

A private release microbenchmark compiles the original helper from `8fe80d00`
and the actual changed module with the same optimized toolchain, fat LTO and
one codegen unit. It verifies 128 fictional signed 400-byte messages, rejects
altered inputs, then alternates before/after order across six rounds of
32,768 repeated checks. Median duration is 1.7177 seconds before and 0.01908
seconds after, a 90.0× improvement for this warmed repeated-check mechanism.
This is not whole-application throughput or a whole-Windows CPU prediction.

A same-host native API comparison restores one identical encrypted fixture
before every process: eight offline DMs, two groups, one channel and 208 messages.
Both release workers use the same production-built Go 1.25.9 Moss library, with
its loaded path verified in `/proc`; the original worker is from `3e6790f5` and
the changed worker from `8aa8bb65`. Six rounds alternate execution order. One
initial list warms each process; thirty subsequent `list_sessions` calls form
the measurement. The manual DM-service setting is the same on both variants.

Median process CPU for thirty calls falls from **1.735 s** (range 1.68–1.80) to
**0.720 s** (0.67–0.79), a **58.5%** reduction in this native API workload. A
canonical digest of all returned message contents, identities and permission
metadata is identical in all twelve processes. It is
`6e8d988daa876b1c4e6fd2f61086fb47e4bcfdccf91f0d701c1f532069f0606e`.

Wall-time medians are 4.618 / 4.031 seconds per thirty calls, while per-call p95
medians are 252 / 266 ms. Public Moss and scheduling variance remain visible;
this does not establish a tail-latency improvement or predict owner idle CPU.
These are Linux release API workers, not the rendered Windows application.

## Independent receive attribution

A separate native run uses the same fictional 8-DM/2-group/1-channel fixture,
warms for eight minutes and observes currently owned IPv4 socket ports for 120
seconds. Packet accounting records zero socket drops. Only receive traffic is
captured: approximately 7.52 MB of IP bytes, of which 6.24 MB belongs to the mesh
UDP socket and 31.8 kB is recognized DHT UDP traffic. Mesh UDP is about 83% of
the received bytes; DHT is about 0.42% in this window.

This rejects DHT dominance for this native receive window, not for the owner's
Windows workload. Later IP fragments are skipped, transient TCP sockets can be
missed and transmit attribution is absent. These counters are not a complete
wire budget. No addresses or payloads are retained in the report. Residual
public mesh traffic remains a separate investigation from history verification.

## Configured Windows build

The full application CI at runtime commit `8aa8bb65` passes, including Flutter,
bridge drift, real multi-device DM, Windows/macOS Rust, native audio/video,
Android debug and both desktop installer proof builds. The separate
[configured Windows installer](https://github.com/redstone-md/mosh-flutter/actions/runs/39792369635/artifacts/12432974345)
also passes its source/Moss pin, SHA-256 and production PLUS manifest checks.
Its installer SHA-256 is
`3519659d5b34f9e4382c78213c888d620e8a1b2a7993dd5c443b582e38b3603d`.

Moss remains pinned to `eb79f38`, but the rebuilt shipping Go DLL is not
byte-identical to the previous installer's DLL. A Windows comparison guard
therefore rejects treating the two complete bundles as a one-variable Rust
comparison. The isolated API experiment explicitly loads the original Go DLL
for both variants; it cannot substitute for testing the complete new installer
against the owner's actual saved history.

The [Windows comparison](https://github.com/redstone-md/mosh-flutter/actions/runs/39801262980)
successfully restores one identical encrypted 8-DM/2-group/1-channel fixture,
including 208 messages, before each of six release API processes. Three rounds
alternate execution order. One initial read warms each process; thirty reads
then request personal names, all conversation lists and the selected offline DM.
Returned message bodies and delivery statuses match in every process.

Median process CPU for thirty reads is **2.3125 s** before and **0.453125 s**
after, an **80.4%** reduction in this Windows API workload. Median wall duration
falls from 2.344 to 0.531 seconds. Process CPU is sampled around the loop through
PowerShell, and public network activity remains uncontrolled. This is an
independent Windows confirmation of the history cost, not a prediction of
whole-application idle CPU or traffic. The exported candidate Go DLL reports
the expected Go 1.25.9 toolchain and parent Mosh revision `8aa8bb65` in its build
metadata; the experiment still requires exact DLL hashes for isolation.

## Windows symbol recovery limit

The original installer is independently installed on a Windows runner and its
core DLL hash matches the owner manifest. The original DLL references PDB GUID
`5848b304-90b6-476d-92e8-a85fc9b15d03`, age one. A rebuild from the same source
produces another DLL/PDB pair, GUID
`155941da-7ceb-4228-967d-c143ad50f9d7`. Its text and unwind sections differ.
The rebuilt PDB is therefore rejected for owner-address attribution; no Rust
function names in this report are inferred from that mismatched PDB. The
caller-path reproduction above is an independent same-binary Linux profile.

## Owner follow-up: 15:45 capture

The next ZIP is `cpu-20261022-154514/mosh-cpu-report.zip`, SHA-256
`bbb68351dde01c6f8325df23b47ec1c5ea20cda3faa4fdd03cb4fd8d8c0cd635`.
The shipping Rust/Moss DLL hashes match the configured `8aa8bb65` installer.
The 90.776-second network capture is complete and control-validated, with no
lost events or buffers. The process has warmed for 26 minutes 18 seconds.

| Observation | Previous capture | New capture |
| --- | ---: | ---: |
| CPU, one logical core | 14.148% | 15.466% |
| Working-set median | 239.54 MiB | 119.46 MiB |
| Combined network mean | 1.853 Mbit/s | 2.278 Mbit/s |
| Complete-second median / p95 / peak | 0.714 / 7.379 / 26.211 | 0.880 / 13.176 / 15.334 Mbit/s |
| Statistical Rust / Moss weights | 26.68% / 25.72% | 17.16% / 30.85% |

Whole-application idle acceptance is not achieved. The public network changes
between captures, so these are observations, not a controlled estimate of the
first history fix. Receive traffic is 72.98% and UDP is 92.20% of external
bytes. The reported 100–150 Mbit/s condition is still absent. Instruction,
kernel and unmapped sample counts reconcile to 14,023; 4,343 of 4,346 raw Moss
instruction samples map to the recovered Go ranges. Three do not. Module CSV
weights and raw instruction counts are distinct exports.

## Linked-history reproduction and correction

An independent Linux release API reproduction links two actual installations,
creates a DM with a third installation and verifies delivery before taking the
counterpart offline. A control that stopped the authorizing device immediately
after pairing produced no account proofs; it is rejected as delegation evidence.
The valid run keeps both linked installations alive until a returned message
origin contains the issued one-delegation account certificate.

On `8aa8bb65`, thirty list calls cost 0.05 CPU seconds with the small control
history, 0.73 seconds with 100 additional signed messages, and 1.03 seconds
with 200. A twenty-second sampled run loses no samples. Two approximately
33% inclusive caller branches reach `AccountCertificate::verify` from history
origin verification and local-authority proof validation. This isolates another
history-dependent cause; it does not assign every owner Rust sample to it.

The correction stores only the successful verification fact for the entire
serialized certificate, tagged separately from signature facts in the same
4,096-entry FIFO bound. Subject matching, proof signatures, current membership,
roles and revocation checks remain outside that fact. Invalid chains never enter
the cache, and no lock is held during certificate verification. Identity/roster
certificate validation outside history account proofs is unchanged.

A caller-level snapshot regression fails before correction: twenty unchanged
polls grow real delegation signature checks from two to twenty-two. After the
correction it passes. Additional checks enforce issuer revocation/membership
loss after warming and reject altered delegation signatures or keys even when
the linked device correctly signs the enclosing account proof. All 35 focused
message-deletion tests and 752 native unit tests pass (twenty expected ignored
workers), as do all-target Clippy and formatting. LLVM maps all 97 changed
executable lines in this increment; branch coverage data is unavailable.

## Controlled linked-history comparison

The release comparison restores the same encrypted fictional fixture before
every process: 201 messages, each carrying a real account-delegation certificate.
All outgoing messages are acknowledged before copying the fixture. Earlier
attempts with an undelivered outbox and public discovery produced unstable
latency and are rejected as performance comparisons.

Twenty rounds alternate `8aa8bb65` and `5c793db1` on the same Linux host, with one
warm list call and thirty measured calls per process. Both workers load the
same Go 1.25.9 library. A private compiler overlay disables public discovery,
and every read asserts zero mesh peers; the manual DM-service setting is the
same for both variants. Moss sources and production discovery policy are
unchanged. This isolates history verification rather than public-network work.

| Thirty native list calls | Before | After |
| --- | ---: | ---: |
| Median process CPU | 0.855 s | 0.120 s |
| CPU range | 0.83–0.92 s | 0.12–0.15 s |
| Median elapsed time | 0.883 s | 0.170 s |
| Median per-call time | 29.02 ms | 5.64 ms |
| Median per-process p95 | 30.87 ms | 6.40 ms |

CPU decreases **85.96% for this isolated workload**. All forty processes
return identical content, origin, identity and permission metadata, digest
`8d671f7de9c071cc96b558bb39e1b5b99ff76539d5a44288b1dbb14f0f23d7fc`.
This is not a whole-application idle CPU or bandwidth prediction.

A twenty-second post-fix profile records 2,798 samples with zero loss while
reading the same delivered fixture. Hashing and JSON string serialization lead
the flat user profile; the worker's JSON/stdout protocol is part of that cost.
Remaining certificate checks occur under `DeviceIdentity::open`, separate from
the warmed history-proof cache. Kernel names and inline expansion are unavailable;
the report uses ELF symbols and recorded stacks without inline lookup. This
does not justify a further production change from harness costs alone.

Independent Standards review reports no findings. Spec review identified a
negative-test gap: changing the terminal key could fail the outer signature
before exercising certificate validation. The strengthened two-hop fixture
preserves the linked signer and correctly signed outer proof while altering
an intermediate delegation. Re-review reports no remaining findings. CodeAnt
completed the production-change review at `56d2dc4a` with no inline findings;
the subsequent `d63bb48d` changes only this negative test.

## Linked-history Windows delivery

The [configured installer](https://github.com/redstone-md/mosh-flutter/actions/runs/39812473672/artifacts/12442816760)
uses source `56d2dc4a`, production correction `5c793db1`, Moss `eb79f38` and
the committed release profile. Its SHA-256 is
`d75d60a6ec10e8f8abc2204da6fba5d26e78885f85693e58f21b1c33d496b419`.
Download, checksum, source/Moss pin and production PLUS manifest checks pass.
All five extracted shipping binaries match the accompanying symbol manifest.
The original Rust PDB matches the shipping DLL's CodeView GUID and age;
future owner instruction offsets can therefore be attributed without a rebuild.

The [complete application CI](https://github.com/redstone-md/mosh-flutter/actions/runs/39814315561)
passes at `d63bb48d`: both Rust core lanes, real multi-device DM and linked-device
flows, Linux/macOS/Windows native calls, Flutter tests, Windows bridge UI integration,
binding drift, Android arm64 debug APK and Windows/macOS packaging. The Android
release lane is intentionally skipped for a pull request. Following commits record
only this report.

Owner-side acceptance remains separate. The latest supplied capture predates
this correction. Residual incoming public mesh traffic and Android
background-call/battery work remain open; no merge or release is included.
