# Issue 94: bound idle peer announcement amplification

The owner requested continued diagnosis and correction without waiting for
another physical Windows capture, using local tests and GitHub Actions.
This continues the approved scoped Moss fix and dependency integration.

## Evidence

The second valid Windows capture averages 5.752 Mbit/s over 120.264 seconds,
with a 70.420 Mbit/s complete-second peak. All ETW losses are zero. The first
capture averaged 10.255 Mbit/s; differing public topology prevents assigning
the entire observed reduction to the PRUNE fix.

A standalone optimized Moss binary at `509a3f86`, with the shipping Mosh
configuration, 35 private topic subscriptions and no application publishes,
reproduced substantial traffic. Private Go overlays count successful outgoing
and dispatched incoming envelope bytes without recording contents or endpoints.
The 210-second run sent 99,901 direct `peer_announce` envelopes (33,895,669
plaintext bytes); a sampled interval reached 65.42 Mbit/s in envelope bytes.
No transit relay routes were present. These are not OS wire-byte counters.

The CPU profile attributes 28.58% of samples to envelope sends and 14.96% to
peer announcement handling (inclusive; do not add overlapping percentages).
A second attribution run distinguishes first-seen identities, relearned
identities and actual capability/address changes before selecting a fix.

## Scope and checks

1. Lock down the amplification at the real signed-announcement receive seam:
   increasing transport peers must not turn one discovery announcement into
   an unbounded broadcast to every connection.
2. Reuse Moss's existing bounded gossip fanout and deterministic target
   ranking. Preserve verification, trust filtering, immediate join snapshots,
   self-introduction and meaningful state changes. Change no wire/FFI contract,
   dependencies, persistence, configured timers or discovery endpoints.
   Decouple relay key discovery from complete catalog propagation: exchange
   existing self-signed key announcements during relay setup, keep their exact
   validated copies on live connections, and refuse readiness without a key.
3. Measure identical controlled inputs before/after, including scaling with
   peer count. Re-run the public standalone measurement as indicative evidence;
   its evolving topology is not a controlled A/B.
4. Verify actual messaging, late/simultaneous joins, churn and relayed delivery,
   race safety and the full upstream suite. Use platform CI and real native
   Mosh integrations. Review CodeAnt comments and nitpicks after updating PRs.
   Include a star with more than `D` leaves and a late participant omitted by
   discovery fanout: encrypted private-room and directed delivery must work
   both ways. Lost/reordered key claims must fail closed and permit retry.

PRs remain reviewable and unmerged. Android background calls and physical
battery acceptance remain separate unfinished parts of #94.

## Follow-up after the configured Windows build

The owner confirmed the third capture used run `39544003089` after a full
tray exit, with a saved chat open and its counterpart offline. Mean traffic
fell to 3.043 Mbit/s, but 27.29% of one CPU core and 2.236 Mbit/s incoming
traffic leave idle acceptance unfinished.

A 600-second standalone run at `00bc8cb`, with no application publishes,
reproduces the remaining traffic. Its warm CPU profile spends 36.20% in
signature verification. Announcement/status handlers verify the same claim
again inside the directory update. Consolidate validation at that boundary,
retaining separate identity, direct-sender and signed-capability trust rules.
Do not introduce a signature cache or change discovery/connection policy.
Benchmark identical signed inputs before/after and recheck tampered claims,
legacy direct hints and relay key admission. Separately trace offline-contact
retries; an offline counterpart must not be mistaken for an application-idle
capture with no retained targets.
