# Issue 94: desktop idle measurement

Scope: measure the real native public-API installations from v0.24.1 before
changing transport or scheduling. Desktop excessive network usage is reported;
Android network usage is unconfirmed. Research: [source map](issue-94-background-calls.research.md).
Evidence and limits: [measurement results](issue-94-idle-measurement.results.md).

1. Prepare pinned Moss and the existing independent-installation worker. Add only
   missing test-harness commands needed to reproduce the desktop read sequence.
2. Start isolated disposable accounts in independent processes. Verify actual
   handshake and message delivery before measuring. Compare list-only, open-chat,
   minimized-open-chat and native-service-only states against the same peers.
3. Capture IP byte counts attributed to the workers' sockets, CPU/RSS and the
   existing bounded Moss recording. Validate loopback counting with known packets,
   check capture drops and keep startup separate from steady idle. Run long enough
   to observe the five-minute relay-promotion boundary. Report limits of the Linux
   API stand rather than treating it as a Windows desktop or Android battery test.
4. If the reported scale is reproduced, reduce to a measured source and add a
   caller-visible regression before the smallest fix. Otherwise prepare a bounded
   standalone collector for the installed Windows app; do not change discovery or
   relay policy on a guess. Reuse the existing diagnostics/logging boundaries.
5. Verify changed seams, run relevant checks, commit and publish a reviewable PR.
   Application protocol, storage, dependencies and Moss sources remain unchanged.

Raw traces, disposable keys, peer addresses and debugger URLs stay in
`/root/private/mosh-idle-network`; commit only aggregate evidence. Network traffic
and CPU measurement are distinct: local bridge snapshots are not wire bytes.
Android background delivery remains in #94, but its wake/storage design follows
the measured desktop work and needs the decisions identified in the research.
