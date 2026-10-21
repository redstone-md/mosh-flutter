# Issue 94: offline DM presence publications

## Owner capture

The warmed Windows recording from 18:49 has 120.315 seconds of complete ETW
coverage with zero reported drops. Mosh had already run for 745 seconds.
It records 8,499,400 transmitted and 14,610,652 received external bytes:
1.537 Mbit/s combined, with a 14.37 Mbit/s maximum full-second bucket.
Process samples show 16.45% of one logical CPU core and median RSS 140.7 MiB.
The 107 anonymous endpoint aliases are not a count of connected peers.
The report has no executable hash. The prior 17:06 capture began 28.5 seconds
after launch; its 1.139 Mbit/s and 18.61% CPU are not a controlled comparison.

## Reproduction and change

The private native workload restores eight acknowledged fictional DMs with
eight distinct offline contacts, two groups and one channel. The baseline
uses the release Rust facade at `99cf73f0` with a counter-only build of the
unchanged Moss pin `cbfb21e1`. After ten minutes of warmup, both two-minute
windows produce 440 `Hello` and 440 `DeviceIdentity` publications. The identity
payloads account for 686,840 of 881,760 application publication bytes (77.9%).
Opening no chat does not remove this service work.

The fix retains fast initial negotiation and connected keepalives. Established
offline sessions use bounded presence retries; unchanged identity advertisements
follow those probes. New text or a usable transport path wakes the probe;
claim/epoch changes bypass suppression after fresh identity validation.
No bridge, wire, stored schema, dependency or Moss source changes are required.
See the [scope and risks](issue-94-idle-presence.plan.md).

## Verification

Seven MemoryNet/runtime regressions cover restored/lost sessions, initial and
connected cadence, path/user wakeups and a returning peer after an hour of
lost packets. With the original fixed two-second policy, the hour scenario
fails with OpenMLS `Generation is too far in the future`; restoring the bounded
policy passes. This is evidence for that scenario, not arbitrary-duration MLS
recovery: sender-generation windows and the existing recovery protocol remain.

A separate recorder-backed integration uses independent native API processes
with real Moss, encrypted redb and MLS. It bounds actual own-publication counts
while a contact is offline, then restarts that contact and verifies text delivery
and authenticated Connected state. Before identity suppression, that same
30-second count is 18 and fails the limit of 12; the corrected test passes.
The count excludes forwarded traffic and is not a whole-network byte budget.

The full Rust unit suite passes (742 passed, 20 ignored). Four native-call
scenarios pass with the real media engine. Clippy passes with warnings denied.
Raw captures, fictional profiling identities and profiles remain private.

## Acceptance limits

The baseline native foreground/background carrier-counter rates are 0.422/0.627
Mbit/s and process CPU is 6.65/6.28% of one core. These counters omit some carrier
traffic and are not equivalent to Windows ETW totals. Public-mesh conditions
vary between windows; application publication counts isolate this change more
reliably than the aggregate network rate.

Whole-application Windows idle acceptance remains open, as do Android background
incoming calls and battery measurements. This change must not close issue #94.
