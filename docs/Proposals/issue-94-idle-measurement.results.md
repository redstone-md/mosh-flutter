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
