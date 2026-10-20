# Issue 94: first desktop idle measurements

2026-10-21. Stand and collector prepared; the diagnostic stage awaits a valid
capture from the reporting Windows machine. Issue #94 remains open.
The reporting Windows machine and physical Android battery/background-call
acceptance remain unmeasured. No transport policy or application timers changed.

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
- Downloaded package SHA-256 and all six source files were verified against
  the repository, allowing Windows line-ending conversion.
- Standards review: no findings. Spec review: one result-visibility finding,
  fixed and re-reviewed in `82a2b517`.

Local Rust checks: formatting and all-target Clippy with `-D warnings` passed;
the unit suite passed 733 tests (20 ignored) and `device_link_flow` passed
14 tests (five media-dependent/worker entry points ignored). The real stand
separately exercised the added list/viewed fixture commands. Broader native
integration and the platform CI matrix are separate from Windows collector
verification; no physical desktop/phone end-to-end acceptance is claimed.

Built-in API references: [logman](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/logman-create-trace),
[ControlTrace](https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-controltracew),
[Get-WinEvent](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1).

## Next decision

Collect the two-minute Windows report in the observed idle state and record the
app version, chat/window state and the exact units/source of the “100–150”
reading. This establishes whether the observation belongs to Mosh and whether
it is a rate or accumulated transfer. Protocol/discovery/relay attribution then
uses the measured dominant category and existing diagnostics. Do not close #94
or claim an idle-resource fix from this diagnostic stage.
