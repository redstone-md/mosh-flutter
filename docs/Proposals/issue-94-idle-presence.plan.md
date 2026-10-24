# Issue 94: bounded retries for an offline saved DM

The 18:49 Windows capture is lossless and starts 745 seconds after launch.
It averages 1.537 Mbit/s and 16.45% of one logical CPU core. The prior capture
was 1.139 Mbit/s and 18.61%, but started only 28.5 seconds after launch;
different topology and startup age prevent a causal before/after comparison.
Whole-application idle acceptance remains open.

A private counter-only Moss build at cbfb21e, with the unchanged release
Rust facade at 99cf73f0, restores eight acknowledged fictional DMs with
distinct offline contacts, two groups and a channel. It observes about four
`Hello` and four `DeviceIdentity` publications per second. Each publication
creates a fresh MLS message even though no application state changed.
The counters separately measure global peer exchange and relay repair;
reducing application publications does not eliminate those costs.

## Scope

- Keep initial MLS negotiation at the existing two-second retry cadence.
- For a restored or lost established DM, back off Hello retries from two
  seconds to a maximum of thirty seconds, using the existing service tick.
- A newly available direct/relay path or newly admitted user text wakes that
  retry immediately. Only authenticated contact traffic establishes Connected.
- While offline, retry an unchanged identity claim alongside Hello. A changed
  validated claim or MLS epoch bypasses suppression. Connected identity retry,
  device admission, recovery and revocation retain their existing cadence.
- Validate the current claim before comparing it with the last advertisement.
  Record only the last attempt's public signed bytes/epoch/retry stamp; failed
  offline sends retry on the next presence probe. Never reuse cached trust.
- No public bridge/wire contract, dependency, persisted record or Moss change.

## Risks and checks

Use the agreed ADR 0026 runtime commands/snapshots and MemoryNet frame seam,
plus the existing native recorder's own-publication events on independent API
processes with real redb, MLS and Moss.
First reproduce a saved offline DM emitting a Hello every two seconds. Prove
bounded publication counts, actual message recovery with real MLS after loss,
unchanged initial negotiation/connected keepalive, and immediate wake on a path
change or new queued text. Check unchanged claims are suppressed while changed
claims, new epochs and failed sends still retry. Existing real multi-device,
revocation and native-call integrations remain required.

A gossip-only idle reconnect can wait up to thirty seconds for a new probe;
incoming authenticated traffic, user activity and a new transport path wake it.
Transport reachability must never itself manufacture authenticated presence.
Compare the original eight-contact native workload after focused/full Rust,
Clippy/formatting checks, then platform CI and CodeAnt/independent review.
Keep owner captures and profiling keys/data private.

Prior art: [go-libp2p dial backoff](https://github.com/libp2p/go-libp2p/blob/master/p2p/net/swarm/swarm_dial.go)
bounds retries of dead peers and clears backoff after successful connection.
The Mosh retry bounds above are application policy, not a libp2p requirement.
