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
30-second count is 18 and fails the limit of 12; the corrected test records
seven publications and passes.
The count excludes forwarded traffic and is not a whole-network byte budget.

Three secondary module-boundary tests inspect actual control frames after a
signed roster extension, a real MLS epoch transition, and both soft/hard
publication failures followed by a new Hello. They avoid inspecting cache
representation. The primary recorder integration also passes under coverage.

The full Rust unit suite passes (745 passed, 20 ignored), as do 23 independent
real-Moss multi-device scenarios (two ignored workers) and four native-call
scenarios with the real media engine. Clippy and formatting pass. LLVM coverage
executes 36 of 38 changed executable production lines (94.7%); the stable tool
emits no branch records. Both independent review axes have no remaining
findings. CodeAnt completed the production change at `77066b70` without inline
findings; subsequent source changes only add tests/formatting.
Raw captures, fictional profiling identities and profiles remain private.

## Release workload after the change

The candidate is built at `de491a10` with the shipping release profile and
the original eight-contact encrypted fixture. After ten minutes of warmup,
each two-minute window (foreground and background) emits 32 Hello and 32
DeviceIdentity publications: 64,128 application bytes versus 881,760 before,
a 92.7% reduction. These counts come from private native instrumentation;
the separate recorder-backed integration above is independent evidence.

The sampled carrier counters are 0.529/0.681 Mbit/s, versus 0.422/0.627 before.
Both endpoints have twelve transport neighbors, but the candidate directory
changes from 415 known addresses at the foreground endpoint to 862 at the
background endpoint; the baseline has 472/471. This local directory count is not
the public network's population: admission and directory eviction also affect
it. Peer-announcement envelopes alone
total 3.78/5.82 MB across the two candidate windows. The application's bounded
publications therefore do not establish a whole-network bandwidth reduction.

Observed native CPU is 6.03/5.29% of one core, versus 6.65/6.28 before. Besides
public topology, the candidate's supplementary debug recorder failed to open
its missing output directory while the baseline's recorder was active. Native
counters and CPU sampling completed, but this configuration difference also
prevents attributing the CPU change to the fix. Repeat any causal CPU comparison
with matching recorder settings. The native workload does not render Flutter.

Both candidate windows still send 1,920 relay requests (668,160 envelope bytes)
for eight offline explicit targets. The follow-up isolates their independent
retry policy: [proposed Moss extension](issue-94-explicit-retry.plan.md).
Target-specific diagnostic counters subsequently confirm actual overlapping
explicit pipelines and attribute all relay requests in a separate two-minute
interval to those eight fictional contacts; details are in that proposal.

The configured [Windows installer at de491a10](https://github.com/redstone-md/mosh-flutter/actions/runs/39668058526/artifacts/12379197516)
was downloaded and checked against its SHA-256 sidecar, source/Moss commits and
mainnet PLUS manifest. SHA-256:
`6bb975f432a5954737ec62e48cfd40e5a2f269261b9532f3de46706465bfa94b`.

## Acceptance limits

The baseline native foreground/background carrier-counter rates are 0.422/0.627
Mbit/s and process CPU is 6.65/6.28% of one core. These counters omit some carrier
traffic and are not equivalent to Windows ETW totals. Public-mesh conditions
vary between windows; application publication counts isolate this change more
reliably than the aggregate network rate.

Whole-application Windows idle acceptance remains open, as do Android background
incoming calls and battery measurements. This change must not close issue #94.
