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

Mosh pins `00bc8cb` in [PR 96](https://github.com/redstone-md/mosh-flutter/pull/96).
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
