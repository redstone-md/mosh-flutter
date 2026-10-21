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


## Follow-up after the fourth Windows capture: discovery degree

The next validated owner capture still averages 3.083 Mbit/s, versus 3.043
previously. Its last minute uses 26.86% of one logical CPU core; the earlier
handler optimization did not establish satisfactory application idle use.
The process started only 42 seconds before this capture, so its whole-window
CPU change is not a controlled comparison.

Private 180-second optimized Moss runs isolate the transport layer: 35 topics
produce 50 connected peers (39 outbound direct), while zero topics still
produce 53 peers and substantial traffic. A diagnostic hard cap of 12 reduces
traffic and CPU, but also changes directory limits and is not the proposed fix.

This iteration separates a soft automatic discovery goal from hard admission
capacity. Derive the soft goal from existing mesh degree settings (12 by
default), retain a minimum outbound population and repair relay-capable
connections. Apply it to known-peer discovery and tracker kicks/seeds only.
Preserve explicit contacts, topic-provider discovery, configured static peers,
LAN discovery, inbound admission, hard MaxPeers, directory capacity, timers,
trust checks, ranking and retry backoff. Capable-relay repair may bypass
public-peer ID ordering while a relay deficit exists, because the remote node
can already have satisfied its own soft goal and never initiate. Ordinary
discovery retains glare avoidance. No new public configuration or wire/FFI
contract. Do not forcibly disconnect existing peers.

Focused selector tests must fail before the fix and cover all three automatic
paths, refill after loss, outbound/relay deficits, static seeds and hard limits.
Real encrypted contact/relay delivery must work beyond the automatic goal.
Measure the candidate with MaxPeers unchanged before integration; compare
public runs as indicative evidence only. Repeat upstream/full native checks,
independent review and CodeAnt comments/nitpicks before the next owner build.


Size-limit exception: existing upstream selector files/functions already exceed
the Mosh limits. This patch keeps their edits local and extracts the new budget
policy into a module under 100 lines; it avoids an unrelated rewrite of transport setup.
Go reports statement coverage, not branch coverage. No tracked captures or
production instrumentation are introduced.


Relay-only neighborhood guard: after a direct discovery attempt fails, allow a
new automatic relay only while total neighbors remain below the working goal.
Otherwise direct-outbound repair could add relayed peers indefinitely without
satisfying that quota. Preserve established relays and explicit/provider paths.
Verify the actual dial/fallback seam with real TCP nodes at and below the goal.

## Follow-up after the fifth Windows capture: diagnostic reads

The validated 120.943-second owner capture averages 1.139 Mbit/s and 18.61%
of one logical CPU core. Its process is only 28.5 seconds old at capture start;
idle acceptance remains open. Profile the optimized real native facade with
an offline counterpart and with the UI's list/open-chat polling pattern.

The trace exposes repeated complete mesh reports while maintaining and listing
saved DMs. Share one current observation across the reachability logging pass,
and one across a returned conversation list. Derive each row's path and filtered
diagnostics from that same observation. Keep fresh reads between operations,
failed-report behavior, authenticated liveness and all publication/routing paths.
Use the existing transport and public snapshot seams; add no cache, timer,
public API, FFI symbol, schema or dependency. Verify constant read cost across
chats plus direct/relayed/offline transitions and failed reports before rerunning
native integrations, independent review, CodeAnt and the configured installer.

Size exception: `snapshot_with_mesh` retains the existing `SessionSnapshot`
field literal over 50 lines, with one constructor for the whole native shape.
