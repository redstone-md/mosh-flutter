# Issue 94: explicit offline connection retries

The native counter reproduction attributes overlapping connection pipelines and
relay requests to the eight saved offline DM counterparts. The fix coalesces each
target's pipeline in Moss; Mosh opts into the generic thirty-second maximum
failure gap. Other consumers retain fixed default gaps. Neither PR closes #94:
public peer exchange, whole-Windows resource acceptance and Android background
incoming-call/battery acceptance remain separate work.

## Sources and workload

| Variant | Mosh source | Moss source |
| --- | --- | --- |
| Before | `de491a101c679fba12aa9ba778d58e36f1ff038c` | `cbfb21e1fb883cec535085cd31f08534eb571681` |
| After | `3e6790f532b443e52ff83b9f12555ca8aab1151b` | `eb79f38e4ef9380b5b398d161a42c65c17b1e4c4` |

Both Linux release API workers restore the same fictional profile: eight offline
DMs, two groups and one channel. Each warms up for ten minutes, then records a
120-second foreground window and a 120-second background window. Foreground
polls names, conversation lists and one offline DM once per second; background
has no UI/API polling. This exercises the native runtime, not a rendered desktop.

The processes run sequentially so the copied transport identities cannot collide.
Both runs enable the recorder, assert a nonempty capture and verify the expected
shared library in the process map. Private Go overlays add counters without
changing production control flow. Changed production files are regenerated from
each pinned source before inserting counters. Worker/library hashes and overlay
manifests accompany the private recordings; captures and fixture keys are not
published.

## Matched counter windows

All four windows complete with eight retained explicit targets. Counts are
native counter deltas; relay requests are attributed to those eight fictional
offline counterparts. Neither window contains another application-level
`Moss_ConnectToPeer` call.

| Count per 120 seconds | Before foreground | After foreground | Before background | After background |
| --- | ---: | ---: | ---: | ---: |
| Explicit pipelines started | 160 | 22 | 160 | 21 |
| Starts overlapping an existing pipeline | 160 | 0 | 160 | 0 |
| Outgoing offline-target relay requests | 1,912 | 268 | 1,920 | 282 |
| Hello publications | 32 | 32 | 32 | 32 |
| DeviceIdentity publications | 32 | 32 | 32 | 32 |
| Application ConnectToPeer calls | 0 | 0 | 0 | 0 |

The new scheduler removes measured overlaps and reduces explicit starts by
86–87% and offline relay requests by 85–86%. App publication counts remain
unchanged from the earlier Mosh presence fix.

The following are indicative resource observations, not an isolated causal
estimate. Incoming public announcement volume differs substantially despite
similar neighbor counts; do not attribute the entire CPU/carrier difference
to explicit retry scheduling.

| Observation | Before foreground | After foreground | Before background | After background |
| --- | ---: | ---: | ---: | ---: |
| Neighbors, start → end | 13 → 13 | 14 → 14 | 13 → 13 | 14 → 14 |
| Incoming peer-announcement envelope bytes | 3,218,117 | 837,474 | 1,750,418 | 1,393,495 |
| Outgoing peer-announcement envelope bytes | 2,781,938 | 450,548 | 2,043,042 | 786,066 |
| Partial combined mesh carrier, Mbit/s | 0.709 | 0.345 | 0.532 | 0.433 |
| API worker CPU, one logical core | 6.09% | 3.92% | 4.36% | 2.98% |

Envelope bytes overlap carrier bytes and must not be added to them. Both captures
are nonempty (5,294,722 and 5,237,933 bytes respectively). Recorder sizes are
artifact sizes, not a network-volume measurement.

## Behavioral checks

- A real TCP endpoint accepts Noise handshake bytes but stalls: twenty repeated
  registrations caused twenty-one concurrent handshakes before the fix. The
  fixed scheduler keeps one active pipeline.
- A changed route and a fresh signed address supersede an unfinished handshake.
  Stop closes blocked handshakes and a restarted node connects successfully.
- Actual maintenance/socket counts distinguish omitted fixed spacing from the
  opt-in exponential policy. No test-only manual scheduler drives this check.
- A three-node relay regression confirms an authenticated relay path and sends
  encrypted private-room and directed messages both ways. It passes five
  repetitions, including the admission/cancellation race caught during review.
- Full upstream Go tests, focused race tests, `go vet` and formatting pass.
  Changed-line coverage mapped from Go statement blocks is 151/178 (84.83%);
  intersecting statement coverage is 197/217 (90.78%). Branch data is unavailable.
  [Moss CI](https://github.com/redstone-md/moss/actions/runs/39691818266)
  also passes Linux, Windows and fast-package race lanes.
- Mosh: 745 Rust unit tests pass, with twenty expected ignored workers; all-target
  Clippy and formatting pass. All 23 real multi-device DM scenarios, four native
  audio/video scenarios and the independent-process offline presence check pass.
- Independent Standards review: zero remaining findings. Independent Spec review:
  zero remaining findings. CodeAnt completed both current code reviews with no
  unresolved inline suggestions; none were resolved without a verified fix.

Native audio/video CI passes on Linux, macOS and Windows. Flutter tests, native
device linking, bridge-binding drift, Windows bridge UI integration, both Rust
core lanes, multi-device DM flow and the Android arm64 debug build also pass.
Both the PR's Windows proof installer and macOS DMG packaging jobs pass, including
native chrome/menu checks. The entire
[Mosh code-check run](https://github.com/redstone-md/mosh-flutter/actions/runs/39692293854)
finishes successfully at code commit `3e6790f5`; the following commit records only
this report and the plan's acceptance status.

## Delivery and limits

The [configured Windows installer](https://github.com/redstone-md/mosh-flutter/actions/runs/39692467913/artifacts/12389848643)
is built from the After source above. Download verification passes: valid PE
header, matching SHA-256 sidecar, exact source/Moss pins and a mainnet PLUS
manifest with purchases configured, billing origin `https://billing.mosh.run`
and the production public issuer pin. Installer SHA-256:
`cdd6bb6028266f1a68de4e88b64ccbd83435f21407b2396ebeef6384dcb739c1`.
The setup executable is 55,790,961 bytes. No merge or release is included in
this increment.

For the remaining owner-side Windows acceptance, install this exact EXE after a
full tray exit, retain the eight-offline-DM profile and let it warm for ten
minutes. Run `Start.cmd` from the matching
[network collector](https://github.com/redstone-md/mosh-flutter/actions/runs/39692293832/artifacts/12389126609)
with the offline chat open and no calls/transfers. Its 120-second
`mosh-network-report.zip` supplies process byte/CPU counters and ETW loss checks.
The collector ZIP checksum has also been verified.

Incoming peer announcements remain a residual source of traffic. Native envelope
and carrier counters are partial instrumentation, not full OS wire-byte totals.
The public network's neighbors and announcements vary between runs; worker CPU
also shares the host with verification jobs. These measurements establish work
attribution and scheduler behavior, not a controlled whole-application bandwidth
or battery budget. The reported 100–150 Mbit/s idle condition has not been
reproduced by the supplied complete owner measurement.
