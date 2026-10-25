# Issue #94: readiness integration and Windows GUI results

## Outcome

Mosh `b81f5f1367239709911c602ba399c9e061404fd4` pins tested Moss
`fcdc3383601cf3fb5232ba1ae1ffe262b552555e`. Its configured Windows installer
builds, installs, opens a real saved chat and preserves the synthetic history.
All applicable platform CI jobs pass. Both ordered Windows comparisons pass.

The complete-application observations do not establish a consistent CPU
improvement. The earlier [paired wait benchmark](issue-94-direct-peer-wait.results.md)
remains evidence for reduced allocation in the context-aware wait; its
percentages must not be presented as whole-Mosh savings. Issue #94 stays open.
No merge or release is performed.

## Integrated source and behavior checks

The product change is the sole Moss gitlink plus its integration plan on
`perf/desktop-idle-network`, in [Mosh PR #96](https://github.com/redstone-md/mosh-flutter/pull/96).
The previous pin is `979a63459e7327aec5a318b108d0382a8f5b091c`.
[Moss PR #30](https://github.com/redstone-md/moss/pull/30) is stacked on #29;
its private notification implementation preserves that baseline's discovery,
retry, cancellation and authorization behavior.

Application source under `lib`, `mosh-core`, `windows`, `macos`, `android`,
assets and their toolchain/manifests is unchanged from `aa17f31e`. No schema,
Flutter/Rust API or binding change is introduced by the pin update.

- Local Go 1.25.9 C-shared preparation passes. Existing real-process
  `directed_packets` and `idle_dm_presence` tests pass: packet/stream callbacks
  coexist, offline retries remain bounded and delivery resumes after reconnect.
- [CI 40152603399](https://github.com/redstone-md/mosh-flutter/actions/runs/40152603399)
  passes all 13 applicable jobs at `b81f5f13`: native calls on Windows/macOS/Linux,
  device linking, multi-device DM, GUI integration, Rust formatting/lint/tests,
  Flutter tests, binding drift and desktop/Android packaging. Android release
  publishing is intentionally skipped. Windows collector checks also pass in
  [run 40152603384](https://github.com/redstone-md/mosh-flutter/actions/runs/40152603384).
- The pinned Moss head separately passes Linux/Windows full suites, mesh/fast
  race checks, strict/repeated mesh, 25-node load and the memory gate in
  [run 40150783981](https://github.com/redstone-md/moss/actions/runs/40150783981).
- Independent Standards and Spec reviews find no integration/harness defects.
  Ten measurement parser/comparison tests, Python compilation and workflow
  lint pass. Actual Windows execution validates fixture reuse and DLL loading.
- The current all-page CodeAnt audit finds no unresolved inline findings or
  summary nitpicks on Mosh #96. Its historical manual review predates this pin.
  Moss #30's one test-scheduling nit is fixed; this is not a final-head CodeAnt
  approval.

## Verified Windows installer

[Configured run 40152604248](https://github.com/redstone-md/mosh-flutter/actions/runs/40152604248)
passes with the committed full release profile: the parallel-codegen override
is skipped. The public PLUS manifest specifies Solana mainnet, configured
purchases and `https://billing.mosh.run`, with the independently pinned issuer.

[Installer artifact 12583388260](https://github.com/redstone-md/mosh-flutter/actions/runs/40152604248/artifacts/12583388260)
contains `mosh-0.24.1-setup.exe`. Its SHA-256 is
`0aa8593c0ccd0793d2e22b28bcd9d6d0ab5c10e256d7ebad6f759776d96fffff`.
The ZIP API digest and CRCs, checksum sidecar, source/config manifest and all
five extracted shipping hashes pass. Matching native symbols are retained in
[artifact 12583383333](https://github.com/redstone-md/mosh-flutter/actions/runs/40152604248/artifacts/12583383333).
The original Rust DLL/PDB GUID is `{48B12AE6-B5B7-4E23-91E9-09FEB735B374}`,
age 1; DLL/PDB GUID/age and PDB SHA-256 match.

The packaged Moss DLL is Go 1.25.9, C-shared and trimpath-built; its SHA-256 is
`31dd49c33ef32c029ba54a439edcafc2dcea854c2c516e21863b9e918fd44248`.
Its embedded VCS revision is the parent Mosh build `b81f5f13`; the actual Moss
source pin is verified independently through Mosh's git tree. The compatible
Linux Inno extractor reports 63 multipart checksum-readback warnings. Five
shipping hashes are independently checked; this is not an all-assets CRC claim.
Native Windows installation and GUI execution pass on both comparison hosts.

Installer ZIP SHA-256:
`cf0267aab998cd5d6b65f4d479a32ef31cff694693a24f1eb0ec9b48ca6f37ba`.
Symbols ZIP SHA-256:
`bcaafdb5a4c27f29384e35f6b97d6a11c7ca0cb8c18ff12861a0b67b2fa3bbdb`.

## Whole-application comparison method

[Run 40154729681](https://github.com/redstone-md/mosh-flutter/actions/runs/40154729681)
passes both jobs at measurement source
`6880b6e14f51a182d51db2d094d2da840f42f1a9`.
Both hosts run Windows Server 2025 10.0.26100, image `20261021.278.1`, with
two cores/four logical processors. The before/after host is EPYC 7763;
the after/before host is EPYC 9V45. Their results are not pooled as one benchmark.

Each job first installs the actual new package, establishes eight real DMs
with 100 acknowledged messages each, two groups and one channel, and opens
the saved offline chat/composer through the new EXE. After closing it, native
inventory retains all 800 bodies and zero pending invitations.

The job then restores the previous verified `aa17f31e` application and creates
two copies differing only in `moss.dll`: shipping `979a634` versus the exact
`fcdc338` DLL from the new installer. Other four binary hashes remain identical.
Fresh EXE/Rust DLL builds can differ even at unchanged application source;
holding those binaries fixed isolates the Moss substitution. The actual new
package's GUI smoke is distinct from these controlled application copies.

Both observations reuse the same saved fixture and identities on their host.
Reuse requires GitHub Actions and an owned synthetic marker. Each variant
warms for 480 seconds, then records separate 90-second visible/minimized
windows. HWND visibility/minimization and target PID are checked before/after.
The collector verifies process-attributed network capture and its control.
The comparison retains the 8/2/1 inventory and body SHA-256
`c21241d354aee8750eed51232ab487bed2121eb65d9aa7eae00d6d37f4160def`.

## Observations

CPU is percent of one logical core, derived from process counters; divide by
four for the corresponding machine-total percentage on these hosts. Traffic
is external TCP/UDP send plus receive over the network interval, in Mbit/s.
Memory is median process working set in MiB, not retained Go/Rust heap.

| Order / host | Moss | Window | CPU, one core | External Mbit/s | Working set MiB |
| --- | --- | --- | ---: | ---: | ---: |
| Before/after, 7763 | Before | Visible | 10.632% | 0.1274 | 116.95 |
| Before/after, 7763 | Before | Minimized | 9.858% | 0.1761 | 113.73 |
| Before/after, 7763 | After | Visible | 7.200% | 0.2425 | 114.62 |
| Before/after, 7763 | After | Minimized | 10.619% | 0.1259 | 116.34 |
| After/before, 9V45 | Before | Visible | 5.377% | 0.1039 | 108.61 |
| After/before, 9V45 | Before | Minimized | 5.779% | 0.1445 | 109.98 |
| After/before, 9V45 | After | Visible | 6.371% | 0.1219 | 110.32 |
| After/before, 9V45 | After | Minimized | 5.198% | 0.1682 | 107.63 |

CPU changes direction between the two visible comparisons and between
visible/minimized windows. These observations establish neither a consistent
whole-application gain nor a causal regression. Public network activity and
topology vary; topology after each window is not independently recorded.
Two ordered pairs are not a statistical performance claim. Sequential
visible/minimized windows also do not isolate minimizing as a cause.

Mean traffic is 0.104–0.242 Mbit/s across all windows. The largest complete-second
peak is 4.097 Mbit/s (baseline); the candidate's largest is 3.817 Mbit/s.
Neither reproduces the owner's original 100–150 Mbit/s report. This does not
prove that an intermittent incident cannot recur. Working sets in these
windows do not establish a heap leak or explain the owner's larger footprint.

## Data fidelity and caller limits

Both artifacts have 59 expected JSON files. API digests, ZIP CRCs, exact names,
source/installer/DLL identities, fixture goldens, binary isolation and reuse
flags are independently checked after download. Every network control passes,
all ETW loss counters are zero, and protocol, per-second and anonymized-peer
byte sums reconcile. Zero-traffic complete seconds are included in rate summaries.

All eight selected-process caller totals reconcile with their raw instruction
totals. The baseline minimized export on the before/after host additionally
rejects one sample classified as foreign/ambiguous process; its selected total
remains 11,097. No other rejected weight is reported. This filter exclusion
is recorded rather than treated as missing selected-process CPU.

Candidate caller profiles recover software rasterization (`d3d10warp`) and
DM-list work, with broken Go/native ancestry still present. Sampler weights
do not conserve OS process CPU, so these identify callers rather than measured
CPU ownership or patch savings. Software rendering on a VM is not proof of the
same dominant cost on the owner's GPU. Native `WM_SIZE` handling reaches the
Flutter controller; these stacks alone do not establish a broken minimize
lifecycle or justify changing production polling/rendering policy.

[Before/after artifact 12585425657](https://github.com/redstone-md/mosh-flutter/actions/runs/40154729681/artifacts/12585425657)
SHA-256:
`350196ecd9c5f82c2a3781d88c2c1d8844d58fb11d5e6f3b7b28deddbf03760a`.
[After/before artifact 12585470499](https://github.com/redstone-md/mosh-flutter/actions/runs/40154729681/artifacts/12585470499)
SHA-256:
`e3b0ecccf413fe0dfd54a002782da91803d0c7778e2340e274e29180fdf15f11`.
The artifacts exclude raw traces, fixture stores, keys, binaries and symbols.

## Remaining acceptance

The current owner capture still belongs to `aa17f31e`, not this installer.
The next physical-desktop check is the verified new installer, a full tray exit
before installation, ten minutes in the same offline-chat scenario, then the
ordinary `Start-CPU.cmd` report. Existing-trace reprocessing is not a new
measurement. The new original symbols remain available for its analysis.

Android background incoming-call delivery is not implemented by this Moss
update. Physical Android lifecycle, incoming-call and battery measurements
remain part of open issue #94. Passing the foreground/platform integration
checks does not close that combined acceptance.
