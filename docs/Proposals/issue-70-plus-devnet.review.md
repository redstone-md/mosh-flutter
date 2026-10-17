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

## PR 89: CodeAnt review

[PR 89](https://github.com/redstone-md/mosh-flutter/pull/89) is on
`feat/plus-devnet`. All three inline findings were accepted, reproduced and
corrected; GitHub confirms their threads resolved:

| Thread | File | Correction and verification |
| --- | --- | --- |
| `PRRT_kwDOTpdkls6tapLt` | `lib/src/features/plus/plus_config.dart` | Reject empty HTTPS hosts; URL regression failed before the fix and passed afterward. |
| `PRRT_kwDOTpdkls6tap5B` | `test/features/plus/plus_offer_test.dart` | Use tomorrow's expiry instead of a fixed January 2027 deadline; widget test passed. |
| `PRRT_kwDOTpdkls6taqy4` | `mosh-core/src/plus/peers.rs` | Withdrawals do not allocate aliases. Real signatures and encrypted restart prove full-capacity opt-out and rejection of replayed opt-in; regression failed before the fix. |

The user also requested evaluation of the four suggestions in the
[CodeAnt Nitpicks comment](https://github.com/redstone-md/mosh-flutter/pull/89#issuecomment-6227023683):

1. **DO NOT ACCEPT the HTTP-race explanation.** No QR is exposed before native
   order persistence; adoption before that point safely binds the checkout to
   the current account. A separate native race was confirmed and corrected:
   `api/plus.rs` now holds the existing device-link owner across account lookup
   and the PLUS action. The concurrent native-service regression failed before
   the fix and passed afterward. Existing independent-process coverage verifies
   adoption before purchase and rejection after purchase. No reservation, schema
   or bridge change was needed. The concurrency test's 100 ms observation window
   can reduce its sensitivity under extreme scheduler delay; runtime correctness
   does not depend on timing.
2. **ACCEPT offer poisoning.** `channel_runtime/blob.rs` rejects supplied-invalid
   proofs. `conversation/dm_offers.rs` checks the existing canonical invite ID,
   promotes verified duplicates over unsigned fields, and never downgrades them.
   Owner regressions reproduced both poisoned names and copied IDs before the
   fix. The real channel runtime checks legacy-first to signed upgrade without
   dismissing the earlier offer.
3. **ACCEPT legacy DM badge loss.** `plus_identity.dart` uses typed conversation
   kind: a DM uses its authenticated session, while groups/channels still require
   native message provenance. The rendered legacy-DM badge regression failed
   before the fix; the legacy-channel forgery regression still passes.
4. **ACCEPT fixed-size signature decoding as hardening.** The shared Ed25519
   verifier decodes into 32/64-byte arrays using the existing `hex` dependency.
   This removes input-sized decode buffers while preserving strict verification.
   Moss already bounds incoming publishes, so the original suggestion's
   unbounded-allocation implication was overstated. Existing real signature and
   forgery tests validate behavior; rejection tests alone do not measure allocation.

Independent follow-up review reported **0 Standards / 0 Spec findings** for the
packaging changes and these corrections. The existing Windows/macOS workflows
produce configured pilot installers; no private issuer key enters Actions.

Follow-up verification: full Flutter suite **1979 passed / 4 skipped**, native
unit suite **732 passed / 20 ignored**, targeted purchase/certificate and real
channel-offer scenarios passed. Analyze, all-target Clippy, formatting and
bridge regeneration/drift checks passed. The fixed-size signature change adds
no new dependency; checkout serialization reuses the existing native owner.
