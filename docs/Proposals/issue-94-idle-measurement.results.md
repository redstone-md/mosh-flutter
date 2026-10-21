# Issue 94: first desktop idle measurements

2026-10-21. Stand, collector and the first valid Windows process capture are
complete. Root-cause attribution and physical Android battery/background-call
acceptance remain open in #94. No transport policy or application timers changed.

## Stand and method

- Application runtime: v0.24.1 / `6f73fcc18fe43e3fecf9e945e9863fc66af69ac1`.
  Only the existing independent-process fixture gained list/viewed commands.
- Moss: `0effb8bb2cd318d2fb516cd2689083daaa5a1917`, prepared with
  `node scripts/moss-prepare.mjs`; sources unchanged.
- Linux 6.12.105, x86-64, AMD EPYC 7713 host, 16 logical CPUs exposed.
  Native Rust debug worker, not a Flutter-rendered Windows/macOS release.
- Worker SHA-256:
  `220d89d06a991dc1fa61dcbcd3cd5e5fac4eeb70ee4887a39c0d0774eb285474`.
- Moss shared-library SHA-256:
  `536af58fcc41dd87870a34505251ffec198b44e8192a24db33c9024045f1edff`.

Build the fixture with:

```sh
node scripts/moss-prepare.mjs
cargo build --manifest-path mosh-core/Cargo.toml --test device_link_flow
```

Each installation runs the ignored `independent_installation_process` test
with `MOSH_LINK_TEST_API=1`, a separate disposable `MOSH_LINK_TEST_DIR` and
`MOSH_LINK_TEST_PORT=0`. Commands and responses use the existing JSON-line
test interface. Two installations completed a real MLS handshake and exchanged
one control message before measurement; no calls or attachments were started.
Existing bounded Moss debug recordings were enabled for the stand only.

The read sequence attempts one tick per second:

| Phase | Existing API calls |
| --- | --- |
| List | `names`, `chat_list` for DM/group/channel |
| Open DM | List reads plus `dm_poll` and `chat_viewed` |
| Minimized with DM open | Same reads, matching current desktop polling policy |
| Native service only | No UI reads; production native service workers remain |

A DM snapshot at each phase boundary also reads mesh state. The stand simulates
the native read sequence; it does not measure window rendering or OS lifecycle.
There is one DM and no populated group/channel history. Public topology evolves
between phases, so this is not a controlled causal A/B of polling policies.

## Network observations

The public Linux captures do not establish a reliable quantitative baseline.
The initial capture lost 56,952 packets; restricting capture to the host
loopback/uplink still lost 6,637 packets out of 300,019. The observed counters
therefore cannot rule out unobserved peaks or establish exact average traffic.
No claim that the reported “100–150” is explained or disproved follows.

The public stand uses shipping network configuration, without the test tracker
override. The isolated comparison uses the existing loopback tracker override:
separate network ID, one-second announces with jitter, DHT/LAN/NAT mapping and
port prediction disabled. Thus its lower traffic cannot be attributed to any
one setting or used as a proposed production configuration.

The isolated pair completed two rounds of four 15-second phases after a
15-second warmup, with one mesh peer per installation. Capture loss was zero
across 72,861 observed packets. The rates below are RX + TX IP bytes per
installation, including its local tracker traffic, weighted by actual duration:

| Phase | Installation A, kbit/s | Installation B, kbit/s |
| --- | ---: | ---: |
| List | 23.55 | 24.05 |
| Open DM | 24.52 | 24.68 |
| Minimized with DM open | 24.12 | 23.95 |
| Native service only | 23.16 | 23.16 |

All attributed bytes in this isolated run were loopback TCP. This establishes
that the real read sequence worked and did not produce the reported scale in
this small isolated case. It does not bound shipping public-mesh traffic or
accounts with many conversations, and it does not justify a production timer
change. The public and isolated byte measurements are not a before/after pair.

Linux IP byte attribution is an indicative stand measurement. It uses worker
socket ownership from `/proc`, refreshed once per tick, and counts IP lengths
at host loopback/uplink interfaces. The duplicate loopback receive copy and
Docker bridge interfaces are excluded. IPv4 fragments are attributed using the
first fragment. Calibration sends ten 64-byte UDP payloads and requires exactly
920 IP bytes in each direction. No packet payloads are saved.

Short-lived sockets between ownership reads can be missed; historical port
reuse and unparsed IPv6 extension headers are further limits. Do not equate
these counts with exact Windows process accounting, Ethernet wire bytes or
application payload sizes. Debug worker CPU/RSS samples are not release CPU or
battery estimates; no CPU improvement is claimed.

An attempted growing port-filter compiler disturbed sampling cadence and was
also excluded; an unoptimized variant exceeded the kernel filter limit. No byte
rates from these unsuccessful probes are used as baselines. This is a reason
to collect native PID-attributed Windows events, not to tune discovery blindly.

Mesh state from the longer first run independently confirms automatic relay
promotion: at 301.9 seconds installation B reported `supernode_ready=true`,
`nat_type=public` and one `relay_route_count`; later snapshots held four routes.
The other installation also received network traffic without that role.
Route presence does not quantify forwarded bytes or prove the cause of the
owner's reported peak.

## Windows collector and verification

[Collector instructions](../../scripts/network-diagnostics/README.md) use the
already installed Mosh process. No app rebuild, restart or elevated app launch
is required. Only the collector requests elevation for built-in Windows ETW.

The collector discovers the installed Kernel-Network schema and uses the event
payload PID. Send/receive, TCP/UDP, loopback and retransmit are separate. It keeps
per-second bytes and anonymous peer aliases, samples process CPU/RAM, limits the
ETL to 128 MiB and stops its unique session with normal cleanup plus an independent
deadline. Both control bursts must survive capture; ETW losses mark totals
incomplete. The shareable ZIP contains exactly two JSON files, never raw ETL,
endpoint addresses, message data or keys. Raw ETL remains private locally.

Windows Server 2025 / Windows PowerShell 5.1 verification at `82a2b517`:

- [Real Windows integration run](https://github.com/redstone-md/mosh-flutter/actions/runs/39514205345)
  passed installed-schema and payload-PID checks, real UDP send/receive,
  foreign-process traffic exclusion, both control bursts and zero-loss checks.
- Target process: 128-byte UDP payloads every 50 ms; unrelated process:
  1,024-byte payloads every 5 ms. Five-second target totals were 11,904 bytes
  sent and 11,904 received. The noisy process's bytes were excluded.
- An independent failing child confirmed that its error message survives
  the child console closing. UAC parent redisplays the report path/quality
  or failure. Interactive UAC itself was source-reviewed, not automated.
- Downloaded package SHA-256 and all packaged source files were verified against
  the repository, allowing Windows line-ending conversion.
- Standards review: no findings. Spec review: one result-visibility finding,
  fixed and re-reviewed in `82a2b517`.

Local Rust checks: formatting and all-target Clippy with `-D warnings` passed;
the unit suite passed 733 tests (20 ignored) and `device_link_flow` passed
14 tests (five media-dependent/worker entry points ignored). The real stand
separately exercised the added list/viewed fixture commands. Broader native
integration also passed, including 23 multi-device DM tests (two ignored).
The platform CI matrix is separate from Windows collector
verification; no physical desktop/phone end-to-end acceptance is claimed.

Built-in API references: [logman](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/logman-create-trace),
[ControlTrace](https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-controltracew),
[Get-WinEvent](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1).

## Reporting Windows machine: first valid capture

The owner supplied `mosh-network-report-20261020.zip`. Only the two expected
JSON files are present. Archive SHA-256:
`14349580d5381931e866f522707012d20f67213b0454ee67bfa2da02d38f033b`.
Raw contents remain local; the figures below are aggregates only.

- UTC interval: 2026-10-20 23:41:53.600 to 23:43:54.056, 120.456 seconds.
- Windows build 10.0.26200.0; the Mosh process was already running for
  312.9 seconds when collection started. Application version and core count
  are not embedded in this report and have not been inferred.
- `complete=true`, both controls validated; all three ETW loss counters zero.
  Per-second and anonymous-endpoint sums independently equal the byte totals.
- 472,019 target-process events; 266 distinct protocol/address/port aliases
  across the interval. This is not a count of simultaneous Moss nodes.

| Counter | Bytes | Average Mbit/s |
| --- | ---: | ---: |
| Sent | 95,217,142 | 6.324 |
| Received | 59,194,379 | 3.931 |
| RX + TX | 154,411,521 | 10.255 |

UDP contributes 109,163,579 bytes (70.7%); TCP contributes 45,247,942 bytes.
No loopback or retransmit bytes were reported. Here `external` means non-loopback,
which can include LAN traffic; it does not establish Internet egress or billing.
The largest endpoint contributes 2.88%, the largest ten together 22.33%.

The largest complete one-second RX + TX bucket is 56.796 Mbit/s, with
37.247 Mbit/s sent and 19.549 received. Median one-second combined rate is
3.907 Mbit/s. No complete one-second bucket reached 100 Mbit/s. This does not
exclude shorter bursts or a different observation window. Small boundary buckets
at seconds -1 and 120 reflect trace startup/stop relative to the chosen origin;
they contain 343,887 bytes and are excluded from the one-second peak/median.

Process samples span 119.131 seconds: 43.250 seconds of processor time,
equivalent to 36.30% of one logical CPU on average, not 36.30% of the whole PC.
Working set ranges from 269.36 to 298.22 MiB; all 118 samples have a main window.

This confirms substantial process-attributed network use in the owner's reported
idle state. ETW does not identify Moss packet kinds, active relay routes or which
application operation initiated them. UDP dominance and a broad set of endpoints
do not establish relay, discovery or an application retry loop as the cause.

Ranked follow-up candidates, with distinct observations needed:

1. Public mesh maintenance/discovery/reconnect churn: control-frame and dial
   activity dominate even while relay routes remain zero.
2. Transit relay: ready supernode status and active relay routes must coincide
   with forwarded packet counters/events and the traffic intervals.
3. Application metadata/history synchronization: subscribed-topic/application
   frames dominate and correlate with conversation/device state.

Existing chat diagnostics expose Peers, NAT, Supernode and Relay routes without
a new build. These values can narrow the relay hypothesis, but a later snapshot
does not reconstruct relay activity during this captured interval. The existing
bounded Moss recording is the next source for causal packet-kind attribution
if the visible state is insufficient; no production setting is changed yet.

### Owner's subsequent runtime snapshot

The supplied screenshot shows 70 mesh peers (68 direct, two relayed),
`nat_type=symmetric_nat`, Supernode `standby`, one active local relay session,
zero transit relay routes, 471 known peers and three subscribed channels.
The selected DM counterpart is offline and its transport has no route.
Personal names, addresses, peer IDs and session IDs are omitted here.

These counters have distinct meanings in the checked source:

- `relay_session_count` counts established entries in `relayLocals`: this node
  is an endpoint using a relay. It does not count routes hosted for others.
- `relay_route_count` counts `relayRoutes`: zero means no such transit routes
  exist at the snapshot. Together with standby status, this gives no evidence
  for active transit relay at that moment. It does not reconstruct the ETW
  capture's earlier state or exclude gossip forwarding.
- Connected peers are mesh transport connections, not conversation participants;
  known peers are a directory, not 471 live connections.
- `relay_migrated` is emitted by `closeRelaySession` on local-session teardown,
  commonly after upgrading to a direct connection. It is also used on explicit
  revocation, so the event name alone proves neither a successful upgrade nor
  transit service for another pair of endpoints.

Mesh maintenance/discovery/reconnect traffic remains the first candidate.
The pinned implementation already separates connection upkeep from the 250 ms
gossip heartbeat, throttles ordinary probes and prevents overlapping relay
upgrade attempts. Their contribution must be measured; those existing guards
must not be described as missing fixes. The application log can first check
whether repeated connection or application synchronization errors coincide
with the captured idle interval, before requesting a new debug recording.

## Next decision

Use the Windows process capture as the first measured symptom, then correlate
it with runtime mesh/relay and packet-kind evidence. Record the application
version and exact display/source/window of the owner's “100–150 Mbit” reading
when available. Do not close #94 or claim an idle-resource fix from this
diagnostic stage.

## Correlation with the supplied application log

`mosh-20261021.log` has 3,840 lines spanning 2026-10-03 through 2026-10-21.
The ETW interval, 2026-10-20 23:41:53.600–23:43:54.056 UTC, contains zero
application-log entries. The surrounding current launch has 17 lines at
23:36:41: one MLS restoration failure and 16 connect requests across eight
sessions targeting five distinct peers. These requests occur at startup,
not repeatedly during the captured two minutes. The failed restore is a
different session from the selected chat shown in the screenshot.

Most warnings in the full file are older MLS generation/verification errors.
They are not evidence for an error storm during the measured idle interval.
The lack of log entries does not exclude normal application synchronization:
the application logger is selective. Moss event callbacks populate the in-memory
diagnostic ring, not `mosh.log`; the file therefore does not contain the
engine-level stream needed to attribute its network maintenance.

The collector package now also provides `Start-MossRecording.cmd`, using the
installed app's existing bounded recorder. It waits for the owner's normal
tray Quit, launches the same EXE unelevated with a child-local diagnostic
variable and requests three idle minutes after the recorder is detected. It shows
progress, waits for another normal Quit and archives exactly the recording
plus a manifest. The owner then opens the ordinary shortcut. The private ZIP
contains network metadata and must not be published with the source PR.
Recording continues until that Quit or the approximately 64 MiB cap. The manifest
separates process startup, recorder detection, requested interval end and the
time when the launcher observes process exit. A monotonic stopwatch supplies
the duration, including the final wait for Quit.

This trace includes startup and only the engine's supported events/metrics.
Ordinary ping/pong envelopes are not individual debug events; session byte
totals also change when sessions disappear. It may narrow the remaining
hypotheses but is not a complete per-packet-kind byte profiler. Windows tests
exercise real fixture processes for child environment isolation, executable
paths with spaces, recorder discovery and timeout behavior without killing
the application. The actual installed Mosh GUI capture remains an owner step.

The owner's launcher reached both tray exits but failed while calculating report
duration: a negative double overflowed the Int32 overload selected by
`Math.Max(0, duration)`. Replaying the reported value reproduces that exception.
Its magnitude is consistent with subtracting the current date from the Windows
1601 epoch, although the actual returned `Process.ExitTime` was not captured.
Report completion now avoids that property and wall-clock subtraction: it uses
an observed UTC timestamp and the existing monotonic stopwatch. A focused test
checks fractional duration, invalid timing replacement, Russian culture and the
actual ZIP contents. On packaging failure, the preserved `.mossrec` is sufficient
for the next analysis; a new owner capture is not required.

## Owner's engine recording: repeated refusals

The preserved recording is 15,254,487 bytes, SHA-256
`a268064169e8cdbfd021118e9ffe19fa4461248747ce000ceac6dd729c01f065`.
All 92,636 JSONL frames parse; its event span is 0.025–192.297 seconds after
engine startup. It did not reach the 64 MiB cap. Event sequences 1–92,256
are continuous and all 38 drop snapshots report `bus_dropped=0`.
This recording is a new launch, separate from the earlier ETW byte capture.

| Observation | Recorded value |
| --- | --- |
| Inbound `gossip.prune` | 85,272, about 443/s over the event span; peak 831 in a complete second |
| PRUNE spread | 52 peer labels and all 35 local topics |
| Median repeat interval, same peer/topic | 2.250 seconds |
| Confirmed members and claimed subscribers | Zero on every topic in all 38 snapshots |
| Mesh peer count | Grows from two at 5 s to 53 at 190 s |
| Local publishes | 2,027, all DM/group control topics; 2,764,227 payload bytes before fanout |
| Outbound queue drops | 1,605 by the final snapshot |

At 190 s, the currently live session ciphertext counters contain 37,189,132
bytes received and 65,578,735 sent. These are neither a lifetime process total
nor a per-packet-kind breakdown; closed sessions, other network protocols and
wire overhead differ. The PRUNE count establishes a control-traffic loop,
not the percentage of all bytes attributable to it. Local publish fanout is
also visible, but attempted target counts are not confirmed delivery bytes.

### Matching defect in the pinned Moss source

`node_debug_emit.go:emitInbound` maps received PRUNE envelopes to these events.
The checked-in revision `0effb8bb2cd318d2fb516cd2689083daaa5a1917` has a
matching sender-side cooldown defect:

1. `ensureTopicMeshMinimum` falls back to connected peers when nobody has
   claimed the topic, and marks a speculative GRAFT before confirmation.
2. A peer outside the topic answers GRAFT with PRUNE.
3. `handleEnvelope` treats an answer to a recent GRAFT as join choreography,
   even if that peer never claimed the topic. It both sets a two-second block
   and backdates `graftedAt` through `markMeshGraftRefused`.
4. That backdating reduces the configured 30-second sender retry interval to
   two seconds. After the next 250 ms heartbeat, the same stranger is eligible
   again. This matches the owner's 2.25-second median refusal spacing.

A private Go test overlay exercises the actual pinned methods and existing
encrypted-session test fixture without changing any dependency files or opening
network sockets. The existing announce-throttle test passes; the new refusal
case fails in 2.25 seconds with a second write where the 30-second retry bound
requires one. Overlay, test and output are retained privately under
`owner-recording-20261021` in the diagnostic directory. This reproduces the
mechanism in source; exact equivalence of the installed binary is not proven.

The approved upstream correction gives refusals explicit per-peer/topic state.
It preserves the normal retry bound for a refusing stranger and lets a first
positive subscription claim take the faster join path. A later refusal still
takes precedence over repeated claims. Prompt late/simultaneous joins, message
and call delivery, independent topics and connection cleanup are verification
gates. Re-measure bytes afterward rather than predicting the whole traffic
reduction from event counts.

Root `AGENTS.md` forbids unrelated Moss changes. After reviewing this diagnosis,
the owner approved the topic-scoped protocol fix and its dependency integration;
see the [implementation plan](issue-94-topic-prune.plan.md). No shipping timers,
discovery policy or dependency revision were changed during the diagnosis.
Android background calls and remaining traffic sources stay open in #94.

## Implemented topic refusal fix

[Moss PR 28](https://github.com/redstone-md/moss/pull/28) implements the approved
correction at `509a3f86f823723240ab3283dd37426809a3ea30`, replacing Mosh's
`0effb8bb2cd318d2fb516cd2689083daaa5a1917` pin. The pub/sub manager owns refusal
state per peer and local topic; connection health stays independent. A first
positive claim admits a late subscriber immediately, while repeated claims
honor newer refusals. Unsubscribe/disconnect release state; retired direct and
relay sessions cannot recreate it through queued GRAFT, PRUNE or send markers.
Wire format, ABI, discovery policy and configured timers are unchanged.
The existing backoff also preserves configured heartbeat intervals above 30 s.

The same private encrypted-session fixture, 35 topics and one refusing peer,
ran for 8.5 seconds on Go 1.25.9: 175 GRAFTs / 9,975 ciphertext bytes before,
35 / 1,995 afterward, an 80% reduction for this control-loop scenario.
This is not a before/after measurement of the owner's full application traffic.

The complete Go suite passed, including real-network late/simultaneous joins,
churn, repair and delivery without a direct path. Focused regressions passed
under the race detector; vet and formatting passed. Those regressions cover
120 of 124 changed executable lines (96.8%); Go's standard coverage tool does
not report branch coverage. Standards and spec reviews have no remaining findings.

The final CodeAnt inline finding and nitpick were reproduced and fixed: dropped
queue sends do not record retries, and refused mesh admission prevents a GRAFT.

Mosh rebuilt this exact Moss pin; Rust formatting and all-target Clippy passed.
All four real-process native-call checks passed, including encrypted signaling,
media connection, video frame delivery and camera-off/stall handling.

Acceptance still needs a comparable Windows process capture on the corrected
build. The old owner trace remains useful and need not be collected again.
Other traffic sources and Android background incoming calls remain open in #94.
