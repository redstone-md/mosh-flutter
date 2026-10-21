# Issue 94: bound offline explicit-target attempts in Moss

This is a proposed extension of the earlier peer-exchange scope. No upstream
source or dependency pin has changed for this proposal.

## Evidence

The warmed eight-offline-contact workload at Mosh `de491a10` emits only 32 Hello
and 32 DeviceIdentity publications per two minutes, versus 440 each previously.
Nevertheless, both foreground and background counter windows contain 1,920
outgoing `relay_request` envelopes (668,160 plaintext envelope bytes), 480
reachability requests and hundreds of overlay queries. These are native
diagnostic counters, not complete Windows wire-byte measurements.

A separate four-minute diagnostic run tags relay targets against the eight
fictional counterpart IDs and counts active explicit pipelines. Its interval
from second 60 to 180 contains 1,744 relay requests (606,912 envelope bytes),
all tagged to those eight contacts. Each of its 160 newly started explicit
pipelines overlaps an earlier pipeline for the same target. This establishes
both destination attribution and actual overlapping attempts, independently
of assumptions about the global peer directory. Transport neighbors change
from twelve to thirteen during that interval.

`moss/internal/mesh/node_explicit_targets.go` registers each DM counterpart once,
then maintains its own fixed retry interval. `dialExplicitTargets` records the
attempt start and uses only HandshakeTimeout/Heartbeat as its cooldown.
`dialExplicitTarget` runs a direct leg followed by relay fallback but does not
record the outcome through the ordinary discovery retry accounting. Its full
pipeline can outlast the interval; new attempts have no per-target in-flight
guard. `node_peer_discovery.go` already has exponential backoff timed from
completion for discovered peers; registration as an explicit target bypasses it.

The remaining `peer_announce` traffic is larger still: 3.78/5.82 MB across the
same two foreground/background windows. This proposal does not claim to remove
all public peer exchange or establish a whole-application resource budget.

## Proposed scope

The [consumer compatibility audit](issue-94-explicit-consumers.research.md)
separates generic duplicate-attempt suppression from the longer offline retry
policy. The inspected game bridges use address-based `Connect`, but unknown
`ConnectToPeer` consumers may depend on the current recovery cadence. Do not
change their default interval or add product-name checks in Moss.

1. In the isolated upstream worktree, keep immediate explicit registration and
   the direct-then-relay path, including authenticated relay key admission.
2. Allow one in-flight connection pipeline per explicit target. Time retries
   from completion. Keep the longer exponential offline backoff, capped at
   thirty seconds, behind a generic optional policy enabled by Mosh; retain
   the existing default retry interval. A new explicit caller request or usable
   target hint must remain responsive during an active attempt or backoff,
   without creating parallel pipelines. Success resets failure state;
   Stop/restart must discard stale in-flight completion state.
3. Preserve priority over automatic discovery, established relay paths, hard
   capacity and ordinary discovery backoff. Specify the optional policy's
   configuration contract before implementing it; the earlier no-contract
   proposal is superseded by this compatibility requirement. Keep wire formats,
   dependencies and discovery automatic; add no manual network setting.
4. First reproduce repeated/overlapping explicit attempts at the real Node
   boundary with an unavailable target. Cover failure completion, retry bounds,
   success, renewed caller intent and Stop/restart. Verify real signed direct
   and relayed late joins, private messaging and native calls; run full Go/race
   checks and CodeAnt/independent reviews before integrating a new Moss pin.
5. Repeat the private native eight-contact workload with matching recorder and
   counter configuration. Separate own publications, explicit dial work,
   public peer exchange, CPU and complete OS counters in the report.

## Risks and authorization

An unattended target without new caller intent or inbound connection can wait
up to thirty seconds before another maintenance attempt. Do not manufacture
authenticated Mosh presence from transport hints. Incoming peer-announcement
volume and whole-Windows acceptance remain separate checks.

The repository's AGENTS.md says: "Do not modify `moss/` sources or sibling
repositories." The user authorized the upstream explicit-retry extension in
the isolated worktree, then requested a compatibility investigation before
choosing its scope. That investigation is recorded above. No production source,
public configuration contract or dependency pin has changed in this research
step; the optional policy interface remains a proposal.
