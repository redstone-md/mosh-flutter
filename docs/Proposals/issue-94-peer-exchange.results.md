# Issue 94: residual idle discovery traffic

## Owner's second Windows capture

The private `mosh-network-report.zip` covers 2026-10-21 03:30:48.476 to
03:32:48.740 UTC, 120.264 seconds. It reports a complete, controlled capture
and zero lost ETW events/buffers. Independent endpoint/protocol and time-bucket
sums match. Only aggregate measurements are published here.

| Measurement | First capture | Second capture |
| --- | ---: | ---: |
| Duration | 120.456 s | 120.264 s |
| TX | 95,217,142 bytes | 48,586,106 bytes |
| RX | 59,194,379 bytes | 37,876,494 bytes |
| Combined mean | 10.255 Mbit/s | 5.752 Mbit/s |
| Complete-second median | 3.907 Mbit/s | 1.223 Mbit/s |
| Complete-second peak | 56.796 Mbit/s | 70.420 Mbit/s |
| CPU, one logical core equivalent | 36.30% | 30.14% |

The second report has 218,543 events: 64,674,654 UDP bytes and 21,787,946 TCP
bytes. Seventeen seconds carry 57,889,199 bytes, roughly 67% of the capture.
None of its complete one-second buckets reaches 100 Mbit/s; shorter bursts
remain possible. CPU percentages use process CPU deltas over sample elapsed
time, not whole-machine utilization. The reports lack a binary version/hash;
artifact timing is consistent with the first fix but does not prove identity.
Different public peers prevent attributing the entire observed reduction to it.

## Reproduced second cause

An optimized standalone Moss node at `509a3f86`, using Mosh's shipping network
settings and 35 private topic subscriptions, reproduced bursts with **zero
application publishes** and no transit relay routes. Private Go overlays count
successful outgoing and dispatched incoming envelopes without saving contents
or endpoints. This is plaintext envelope accounting, not OS wire-byte accounting.

In 210 seconds the node sent 99,901 direct `peer_announce` copies, 33,895,669
plaintext bytes. A sampled interval reached 65.42 Mbit/s combined envelope bytes.
The CPU profile includes 28.58% of samples in envelope sends and 14.96% in
announcement handling; these inclusive stacks overlap and must not be added.
A second attribution run identifies predominantly first-seen catalog claims,
with some identities relearned after directory eviction. The receive path
forwarded each meaningful new claim to **every connected peer**.

## Correction

[Moss PR 28](https://github.com/redstone-md/moss/pull/28) bounds learned
peer/supernode announcement forwarding with the existing `GossipSub.D` fanout.
Trust filtering happens before selection; the local forwarder's identity salts
the ranking so successive hops do not select the same global subset. Existing
claim verification, meaningful-change checks, cooldowns, own announcements and
immediate join snapshots retain their behavior. Telemetry reuses the selection
implementation with its original hash inputs.

The signed-announcement receive regression uses the same real encrypted-session
fixture before and after:

| Recipients | Before copies / ciphertext bytes | After |
| --- | ---: | ---: |
| 1 | 1 / 358 | 1 / 358 |
| 10 | 10 / 3,580 | 6 / 2,148 |
| 64 | 64 / 22,912 | 6 / 2,148 |
| 200 | 200 / 71,600 | 6 / 2,148 |

The 97% reduction at 200 recipients describes this controlled input, not a
forecast for full-application traffic.

Bounded catalog dissemination exposed a hidden relay dependency: setup could
report success without the remote Noise key. Request/accept now send existing
self-signed key announcements first. The intermediary forwards exact validated
claims cached on live authenticated connections, respecting peer-exchange policy
and relay admission. No new wire fields, ABI, dependencies or timers are added.
Missing/reordered keys fail closed; a late authenticated claim enables retry.
Failed writes and close release the matching session/route and relayed peer.
Existing direct connections keep precedence.

A real TCP star with more than `D` one-direct-slot leaves selects an old leaf
that actually missed a late leaf's key. The bounded-only patch falsely reported
success; the correction establishes authenticated relayed peers and delivers
private-room and directed payloads in both directions, without injected keys.
Other focused regressions cover independent forwarding ranks, source exclusion,
signed status changes, immutable claims, stale/mismatched keys, reordered setup,
failed writes, full relay capacity and score-policy refusal.

## Public-network follow-up

An identical private-overlay harness was rebuilt at final Moss revision
`00bc8cb` and ran for 210 seconds. The common post-warmup window is seconds
90–210, approximately 120.1 seconds in each run:

| Envelope measurement | Baseline `509a3f86` | Corrected `00bc8cb` |
| --- | ---: | ---: |
| Connected peers, first → last | 36 → 51 | 31 → 50 |
| Transit relay routes | 0 | 0 |
| Combined mean | 4.116 Mbit/s | 0.732 Mbit/s |
| Sample-interval median | 0.409 Mbit/s | 0.275 Mbit/s |
| Sample-interval p95 | 19.550 Mbit/s | 2.345 Mbit/s |
| Sample-interval peak | 65.423 Mbit/s | 7.122 Mbit/s |
| Outgoing `peer_announce` copies | 94,536 | 3,593 |
| Outgoing `peer_announce` bytes | 32,065,488 | 1,269,675 |

These are successive public-network runs, not a controlled A/B: different
neighbors and incoming claim bursts contribute to the difference. A second
baseline's common 90–160 s window averaged 2.141 Mbit/s, illustrating that
variation. Rates divide counter deltas by actual sample elapsed time; intervals
are approximately one second, not Windows ETW buckets. Neither DHT/other socket
traffic nor encryption/network overhead is included in envelope accounting.
The final CPU profile samples 10.17 CPU seconds over 210.21 s; topology and
host activity prevent treating it as a whole-application CPU/battery guarantee.

## Integration and limits

Mosh initially pinned `00bc8cb` in [PR 96](https://github.com/redstone-md/mosh-flutter/pull/96).
The complete Go suite passes locally; focused protocol checks pass 20 repetitions
and five race-detector repetitions. Vet and formatting pass. Focused coverage
ranges include 106/118 changed executable source lines (89.8%); Go's standard
coverage tool does not provide branch coverage. Standards and spec re-reviews
have no remaining findings. Available CodeAnt inline comments and nitpicks have
been checked, including the earlier refused-admission race correction.

Mosh rebuilt the pinned library, passed Rust formatting/all-target Clippy and
733 unit tests, and passed all four real-process native call checks, including
video delivery, camera-off and capture-stall behavior. Cross-platform evidence
is published in [upstream CI](https://github.com/redstone-md/moss/actions/runs/39543860324)
and the [Mosh PR checks](https://github.com/redstone-md/mosh-flutter/pull/96/checks).
These checks and the configured Windows installer must finish successfully
before merge; the installer uses the production Mosh+ public issuer pin.

The patch bounds this node's forwarding. Older public peers can still send
excessive announcements; the public mesh changes between measurements. No claim
of zero idle traffic, a fixed whole-application bandwidth target or physical
Android battery acceptance is made. Android background incoming calls remain
separate unfinished work in #94. Raw captures and profiles remain private.

## Third Windows capture: offline saved chat

The owner confirmed a full tray exit and the configured installer from run
`39544003089` (`e53dc266`, Moss `00bc8cb`), without calls or file transfers.
The saved chat was open and its counterpart offline. The new capture covers
12:51:40.486–12:53:41.157 UTC on 2026-10-21, 120.671 seconds, starting about
401 seconds after process launch. Capture/control validation passes, all ETW
loss counters are zero, and independent aggregate sums reconcile.

| Measurement | Second capture | Third capture |
| --- | ---: | ---: |
| TX | 48,586,106 bytes | 12,182,485 bytes |
| RX | 37,876,494 bytes | 33,720,846 bytes |
| Combined mean | 5.752 Mbit/s | 3.043 Mbit/s |
| Complete-second median | 1.223 Mbit/s | 1.199 Mbit/s |
| Complete-second p95, nearest rank | 27.535 Mbit/s | 14.203 Mbit/s |
| Complete-second peak | 70.420 Mbit/s | 24.448 Mbit/s |
| CPU, one logical core equivalent | 30.14% | 27.29% |

TX fell 75.0% relative to the second capture; RX fell only 11.3%. Different
public topology still prevents a controlled causal comparison. None of the
complete one-second buckets exceeds 100 Mbit/s, but subsecond bursts remain
unmeasured. Idle acceptance is unfinished: incoming bytes dominate and the
median/CPU remain substantial.

## Remaining CPU attribution and correction

A 600-second optimized standalone run at `00bc8cb`, with the same configuration
and 35 subscriptions but zero application publishes, reproduces the remaining
traffic. Seconds 400.304–520.397 carry 35,593,438 incoming and 8,480,206 outgoing
mesh carrier bytes, 2.936 Mbit/s combined. These private socket counters exclude
some setup/other sockets and are not a full OS wire measurement. DHT contributes
44,067 bytes in the same window, under 0.003 Mbit/s. There are no transit routes.
Dispatched incoming announcements account for 55,055 copies/18,700,311 plaintext
bytes; carrier/envelope counters overlap and must not be added.

The warm CPU profile (seconds 380–600) samples 21.49 CPU seconds over 220.17 s;
36.20% is in signature verification. Receive handlers verify each peer/status
claim, then the directory-update function verifies it again. A private overlay
assertion observes two actual cryptographic verifications for one received
claim before correction and one after, for all three announcement/status types.

[Moss PR 29](https://github.com/redstone-md/moss/pull/29) consolidates validation
at the directory boundary. Direct-sender identity, peer signatures and signed
capability claims keep separate trust rules. It removes the caller-provided
verification flag, without a signature cache, new wire fields or discovery-policy
changes. Mosh now pins `83b03d3` for this follow-up; PR 28 has merged upstream.

Five optimized, identical-input receive benchmark repetitions on the same Linux
host give these medians, with setup outside the measured loop:

| Claim | Before | After | Allocations before → after |
| --- | ---: | ---: | ---: |
| `peer_announce` | 129.926 µs | 65.721 µs | 8 → 6 |
| `supernode_announce` | 130.941 µs | 66.941 µs | 10 → 6 |
| `supernode_revoke` | 129.675 µs | 65.828 µs | 10 → 6 |

The 48.9–49.4% reduction applies to this handler work, not full-application CPU
or network traffic. Tampered repeated claims, legacy direct hints, capability
trust, relay keys and real late-leaf relayed delivery pass focused checks.
Independent standards and spec reviews report no findings in this follow-up.

A separate 180-second standalone run registers one synthetic absent contact
after second 60, using the actual retained `ConnectToPeer` path. Over the next
120.095 seconds, 327 successful relay-request writes for that contact total
113,796 plaintext bytes (about 0.0076 Mbit/s). This excludes related introductions,
other setup traffic and application-level controls, so it is not an upper bound
on a complete offline DM. It does distinguish those requests from the substantial
general-network traffic already reproduced without any retained contact.

Mosh registers each session/device target once; Moss owns subsequent retries.
For established device-aware sessions, application control routing checks live
device reach and does not fall back to public room publishing when all devices
are offline. Periodic MLS control construction/persistence remains a separate
potential CPU/disk cost; this packet trace does not measure that cost.
