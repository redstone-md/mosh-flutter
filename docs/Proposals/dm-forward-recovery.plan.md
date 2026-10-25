# Bounded recovery of missed DM ratchet generations

The owner reports one-way delivery in an existing Android/Windows DM on
0.24.2; a new DM between the same independent profiles works. Receiver logs
have not yet established the exact error in that installation.

A deterministic real-MLS/MemoryNet scenario reproduces one-way delivery:
one hour of lost Bob-to-Alice frames while Alice-to-Bob traffic continues.
After transport recovery, Alice rejects Bob's text as a generation too far
in the future. The identical scenario fails on both 0.24.1 and 0.24.2.

## Scope

- Opt only DM reception into bounded catch-up after OpenMLS's typed
  `TooDistantInTheFuture` error. Leave ordinary reception and other MLS owners
  at their configured limits.
- Retry on a copy of this installation's own state, temporarily allowing at
  most 65,536 skipped generations. Keep all other configuration, including
  discarded-key retention and old epochs, unchanged.
- Install only after ordinary MLS authentication succeeds; retain the existing
  outer application-proof checks and restore the original configuration.
- Allow one expensive attempt per DM per ten seconds, including refused
  application proofs. Receive-state copies share that budget; it is not durable.
- Change no bridge/wire contracts, dependencies, history schemas or Moss code.
- Fresh authenticated contact traffic reactivates retained `Sent` attempts
  whose automatic retry budget expired. Re-encrypt the original semantic text
  with its existing id and author proof; elapsed time and route availability
  alone do not restart publication. Ordinary automatic retries stay bounded.

## Checks and limits

First retain the failing two-profile runtime scenario. Check restored history,
bidirectional text, delivery receipts and call signaling after recovery. Cover
forged payload/proof rollback, replay refusal, the hard forward bound, budget
sharing, configuration preservation and successful state persistence. Measure
the ceiling case, then run the core suite, lint and existing independent-process
DM/call integrations. Review before providing installer builds.

This cannot reconstruct deleted secrets or repair arbitrary rollback/divergent
epochs. The owner's old chat still needs verification on the resulting build;
a working new chat alone does not identify its exact cryptographic error.

OpenMLS documents `maximum_forward_distance` as the local policy for dropped
application messages: [forward secrecy](https://book.openmls.tech/forward_secrecy.html)
and [group configuration](https://book.openmls.tech/user_manual/group_config.html).
The pinned 0.8.1 sources are authoritative for method signatures and errors.

The single long asymmetric runtime test may exceed the 50-line function limit
to keep the two independent users, real identity exchange, one-hour partition,
delivery/receipt assertions and recovered call signaling visible together.
