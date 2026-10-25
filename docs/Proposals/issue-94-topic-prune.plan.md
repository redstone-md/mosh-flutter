# Issue 94: topic-scoped PRUNE backoff

The owner approved the protocol fix after reviewing the engine recording and
the difference between a narrow timer change and a correct state transition.
That approval covers a separate Moss fix and its Mosh dependency update for
this issue; the general prohibition on unrelated Moss changes remains.

Scope:

- Keep refusal/retry state per live peer and topic. A refused topic must not
  block another chat, or have its cooldown cleared by that other chat's GRAFT.
- Keep the established retry bound for strangers after PRUNE. A real late
  subscriber must be admitted promptly through its positive topic claim.
- Preserve the separate peer-wide health/score exclusion. Subscription traffic
  must not erase an unhealthy peer's exclusion.
- Bound state by local subscriptions and live connections, releasing topic
  state on unsubscribe and connection teardown.
- Keep the wire format, ABI, storage, dependencies and shipping timers unchanged.

Implementation order:

1. Add failing behavior regressions in Moss using the existing recorded encrypted
   sessions: stranger refusal, independent topics, fresh subscriber and health
   exclusion. Extend with retry expiry and unsubscribe/reconnect cleanup.
2. Implement the topic state behind the existing mesh-maintenance seam. Run the
   focused checks, real pub/sub late/simultaneous joins and the complete Go suite.
3. Compare repeated idle control sends with the same scripted scenario before
   and after. Report event/control reductions separately from OS network bytes.
4. Publish a focused upstream stable fix from the exact version Mosh ships, then
   update Mosh's pin to its published commit and verify native messaging/calls.
   Moss's contribution guide defaults to `dev` for active development; this
   maintenance fix targets `main`, matching the shipping pin and recent stable
   fixes, without importing the unrelated divergent `dev` history.
5. Review both diffs, run the relevant checks and produce reviewable PRs/builds.
   Do not merge or publish a release without the maintainer's instruction.

Design reference: [Gossipsub PRUNE backoff](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.1.md).
Use its topic-scoped refusal pattern, preserving Moss's existing use of GRAFT
as a subscription claim; adopting a new wire protocol is outside this fix.

Risks and acceptance: stale/in-flight refusals and simultaneous joins can expose
ordering races. Check those using real dependencies, alongside multiple topics,
disconnect/reconnect and app signaling. The owner recording confirms a repeated
control loop, not its share of all traffic; a public-mesh Windows byte comparison
remains necessary before claiming the reported idle resource problem resolved.
