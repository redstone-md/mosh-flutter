# Issue 70 implementation review

Two independent read-only reviewers applied the `code-review` skill to public
`10e4a711...a2be812c` (three implementation commits) and private
`10f6fa0...c688a95` (two billing commits). The approved
[plan](issue-70-plus-devnet.plan.md), repository instructions and architecture
were the specification/standards sources. Findings below describe those pinned
artifacts. Subsequent corrections preserve the approved scope.

## Standards

- **P1: Account adoption leaves PLUS attached to the previous user.** A desktop
  could purchase before creating conversations and then adopt another account;
  `can_join()` ignored PLUS and the cached owner retained its old root. This
  violated account separation and real runtime security indicators. **Corrected:**
  pending/completed purchases prevent adoption, while every native PLUS command
  resolves its current account. Fresh linking before purchase rebinds an empty
  owner. The real bridge and independent-process linking tests cover both paths.
- **P2: Async completions overwrite a rebuilt controller.** Actions captured one
  Riverpod reference but updated through the notifier's current reference after
  awaits. **Corrected:** build/actions capture their lifetime, continuations check
  it before further effects, and stale completions cannot release a new action's
  lock or overwrite its snapshot. A suspended-read/invalidation regression covers
  the boundary.

No additional material heuristic smells were reported. Feature-local command
adapters remain intentional test seams.

## Spec

- **P1: Channel offers borrow another user's badge.** An unsigned offer could
  claim a cached paid fingerprint beside an arbitrary name/invite, violating
  “Unknown, forged … or mismatched evidence cannot produce a badge.” **Corrected:**
  complete channel offers use an optional signed origin and existing targeted
  invite ownership; native provenance cannot be asserted by serialized input.
  Flutter badges require that provenance. Legacy offers remain ordinary offers.
- **P1: Participant rows bypass legacy-message protection.** All messages supplied
  names/fingerprints, so an unsigned label could inherit paid/own status. This
  violated the same rule and ordinary legacy-user behavior. **Corrected:** selected
  labels carry native-verified provenance, unsigned labels cannot overwrite
  authenticated labels, and neither peer nor own badges attach to legacy claims.
- **P2: Payments beyond 100 signatures never resolve.** Scanning only the newest
  page contradicted acceptance of late correct payments. **Corrected:** persist
  bounded scan progress, advance older pages, then return to the head. A real SDK
  transfer behind 104 failed candidates is found after a verifier restart.
- **P2: Unpaid advertisements exhaust the peer cache.** Unknown withdrawal frames
  allocated durable entries without purchasing, leaving bounded dissemination
  vulnerable to free cache exhaustion. **Corrected:** authenticated withdrawals for
  unknown accounts allocate nothing; known withdrawals retain replay protection.
  The regression checks the encrypted persistence boundary.

No scope creep was reported. Real mobile-wallet/desktop acceptance remains a
manual gate and is not represented by local RPC fixtures.

Standards: 2 findings, worst P1 account adoption; Spec: 4 findings, worst P1 forged
identity surfaces. All six findings have corresponding corrections and tests.
