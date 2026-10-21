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

## Integration and limits

Mosh pins `00bc8cb` in [PR 96](https://github.com/redstone-md/mosh-flutter/pull/96).
Focused protocol checks pass 20 repetitions and five race-detector repetitions.
Full upstream and Mosh platform/native-call CI are required before merge;
results are recorded below when complete.

The patch bounds this node's forwarding. Older public peers can still send
excessive announcements; the public mesh changes between measurements. No claim
of zero idle traffic, a fixed whole-application bandwidth target or physical
Android battery acceptance is made. Android background incoming calls remain
separate unfinished work in #94. Raw captures and profiles remain private.
