# Bounded recovery of missed DM ratchet generations

The owner reports one-way delivery in an existing Android/Windows DM on
0.24.2; a new DM between the same independent profiles works. Receiver logs
have not yet established the exact error in that installation.

A deterministic real-MLS/MemoryNet scenario reproduces one-way delivery:
one hour of lost Bob-to-Alice frames while Alice-to-Bob traffic continues.
After transport recovery, Alice rejects Bob's text as a generation too far
in the future. The identical scenario fails on both 0.24.1 and 0.24.2.

## Scope

- Opt only checked DM reception into bounded catch-up after OpenMLS's typed
  `TooDistantInTheFuture` error. Leave ordinary reception and other MLS owners
  at their configured limits.
- Legacy control handlers that validate their bodies after decryption do not
  get the expanded window. A fresh text or checked call/attachment frame can
  recover reception; subsequent legacy controls use the ordinary window.
- Retry on a copy of this installation's own state, temporarily allowing at
  most 65,536 skipped generations. Keep all other configuration, including
  discarded-key retention and old epochs, unchanged.
- Install only after ordinary MLS authentication succeeds; retain the existing
  outer application-proof checks and restore the original configuration.
- Allow one expensive attempt per DM per ten seconds, including refused
  application proofs. Receive-state copies share that budget; it is not durable.
- Change no bridge/wire contracts, dependencies, history schemas or Moss code.
- Authenticated reconnection or a new contact delivery receipt reactivates
  retained unacknowledged `Sent` attempts whose retry budget expired. Continuous
  unrelated traffic and repeated receipts cannot renew that budget. Re-encrypt the original semantic text
  with its existing id and author proof; elapsed time and route availability
  alone do not restart publication. Ordinary automatic retries stay bounded.
  A session that remained connected needs a fresh successfully acknowledged
  outgoing text before older exhausted sends resume. Every ordinary bounded
  retry encrypts the retained semantic text at the current generation, without
  resetting its counter or downgrading a Delivered row. This recovers in-flight
  ciphertext discarded by catch-up without requeueing an active outgoing batch.

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

Function-length exceptions: the asymmetric runtime scenario, unchecked-control
regression and exhausted-send recovery regression keep their setup, fault and
caller-visible assertions together (up to 100 lines). The existing device receipt
handler remains together at 59 lines so that authorization, receipt settlement
and recovery scheduling retain an explicit order.

## Review decisions

- CodeAnt's repeated-work concern is bounded explicitly: the 65,536-step path
  measured 87 ms in an optimized server build. The per-DM ten-second gate is
  shared by receive candidates and charges rejected MLS signatures and outer
  proofs too. It is synchronous; slower devices still require field validation.
- The ordinary checked-message snapshot copy predates this change in 0.24.2.
  This patch reuses it; unrelated snapshot redesign is outside this fix.
- Continuous unrelated contact traffic no longer renews delivery retries.
  Only authenticated reconnection or a newly acknowledged outgoing message
  permits another bounded cycle. Duplicate and sibling receipts do not renew it.
  Delivered rows remain delivered while offline-sibling retries finish.

## Verification and field acceptance

The one-hour two-user scenario now verifies both fresh text and an older
unacknowledged text, delivery receipts, and call signaling after recovery.
Its original failure is retained against both 0.24.1 and 0.24.2. Additional
regressions cover an unchecked control wrapping genuine future text, Delivered
rows retained for siblings, expired retry renewal, unrelated contact traffic,
normal batch acknowledgements, and fresh ciphertext on in-flight retries.

Standards and Spec reviews independently checked the final boundaries and
receipt ordering. Both reported no remaining findings after their fixes.
The public PR is [#98](https://github.com/redstone-md/mosh-flutter/pull/98).

Field acceptance requires installing the same resulting Windows/Android build
over both existing installations, fully quitting the previous processes first.
Keep the old chat and profiles. Send a fresh text from the previously failing
side, verify text and receipts in both directions, and start a call. If that
old chat still fails, obtain the receiver's exact inbound-frame warning before
claiming that this reproduced mechanism explains the physical installation.
