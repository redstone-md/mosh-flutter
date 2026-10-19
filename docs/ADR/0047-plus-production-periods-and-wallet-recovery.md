# 0047: Production Mosh+ periods and wallet recovery

Date: 2026-10-19. Status: accepted; production activation awaits acceptance.
Extends [0046](0046-plus-devnet-blind-entitlements.md).

Mosh+ supports development and provides an account-bound, locally verified badge.
The completed devnet pilot established checkout and proof delivery. Production
adds two real payment assets, renewal, linked-device continuity and wallet recovery.

## Decision

Keep the native PLUS owner, encrypted installation storage, Riverpod, existing
authenticated conversation carriers and partially blind RSA signatures. The private
billing service receives anonymous series, quotes and wallets, never the Mosh
account subject. It has no treasury signing key. Solana mainnet and devnet have
separate certificate domains, trust pins, storage records and service configurations.

Each mainnet certificate signs issuer key ID, product, valid-from and expiry;
the blinded subject binds it to the Mosh account. A collection of immutable paid
intervals replaces the production single-certificate slot. Early renewal appends
30 days to the scheduling tail, while future proofs remain inactive until their
start. Visibility has its own monotonic counter and writer, independent of renewal.
Peers receive at most the current and next proof and verify locally.

One anonymous renewal series serializes purchases across an account. Its secret,
orders, prepared blind requests, certificates and visibility travel through the
existing encrypted, roster-authenticated device metadata channel. The original
account device initializes the series. Before its first checkout, active roster
members must durably acknowledge it; a committed series survives roster changes.
We do not elect a replacement initializer and risk selling overlapping intervals.

Wallet recovery uses a public pairing page, a short device code, Wallet Standard
sign-in, explicit per-order consent and a separate native destination signing key.
The public QR contains no desktop polling capability. Source token owner determines
recovery authority; fee payer and delegate do not substitute for it. Ambiguous
funding or competing full payments require manual handling.

Consent atomically reserves an issuance slot and joins scheduling authority.
Joining preserves the source tail, including other wallets' reserved intervals,
without exposing their orders. Recover A, purchase again, then recover B retains
the original dates. Two unrelated active schedules cannot silently merge.
An order allows its original issuance and one additional recovery issuance;
retries bind the same blinded message durably. Previously issued certificates
remain valid through their original expiry. No revocation claim is made.

## Consequences

Billing can correlate a renewal series, its orders, wallet ownership and recovery
scheduling lineage. It cannot read the blinded account subject. Small purchaser
sets and timing still permit correlation. Linked devices receive capabilities
needed to complete purchases, so device authorization remains a trust boundary.

Initial checkout can wait for an offline original device or active sibling. Losing
an issuance device before prepared state reaches a sibling may require wallet
recovery. Recovery restores paid periods, not identity, chat history or account keys.
One additional issuance is finite and cannot cover repeated losses indefinitely.

Key IDs permit future trust migration; live issuer rotation is not implemented.
Preserve the existing issuer for every outstanding, future and pending paid order.
Opening existing production orders under another issuer is refused by preflight.

Sales pause blocks new orders while preserving paid fulfillment and recovery.
Normal installers carry explicit network and independently configured public pin;
CI proof builds keep billing disabled. Actual treasury setup, mainnet payments and
mobile-wallet acceptance remain deployment gates in the
[feature guide](../Features/plus-mainnet.md).

## Implementation limits

The PLUS runtime remains one storage owner, split by feature into small impl files;
its aggregate type exceeds the 200-line guideline to retain one persistence and
lock boundary. Transactional merge and DTO construction may exceed 50 lines where
splitting would hide validation from the atomic save. The real-Moss carrier test
keeps one setup/send/hide scenario together. Generated bridge code is exempt.

The integration scenarios in `mosh-core/tests/plus_mainnet.rs`,
`plus_mainnet_recovery.rs`, `plus_mainnet_peers.rs` and `plus_mainnet_sync.rs`
also exceed 50 lines (at most 92). Each keeps one purchase, recovery, peer-proof
or linked-device workflow together with its restart and rejection assertions;
splitting these scenarios would separate the observable result from its setup.
