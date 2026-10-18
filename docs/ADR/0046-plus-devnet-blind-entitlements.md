# ADR 0046: Devnet PLUS entitlement and partially blind issuance

Status: accepted for the devnet pilot in issue 70.

## Context

Purchases need durable independent on-chain verification while peers must verify
a paid badge without contacting billing. A wallet/order must not become the
messenger account identity. Existing Moss identities, MLS leaves and linked-account
roots already have distinct owners and authenticated delegation paths.
Plain account-linked issuance would directly connect a wallet payment to a Mosh
identity. Partially blind issuance adds cryptographic/key-management complexity
to avoid that direct join while keeping peers independent of billing availability.

## Decision

Keep billing in a separate private Node/TypeScript repository. It owns immutable
devnet quotes, unique transaction claims and persist-before-response issuance in
SQLite. It never holds wallet/treasury keys or receives a Mosh account identity.
Use the maintained Solana Pay/Kit parsers and compare atomic amounts with bigint.

Use interoperable partially blind RSA with a pinned public issuer and safe-prime
key generation. Bind the hidden subject to the existing linked-account root;
public metadata contains only the pilot domain, product and shared UTC-day expiry.
Reserve expiry at the durable paid/issuance intent and never extend it on retry.
Persist the native blinding inverse before submitting any request. Reuse encrypted
redb for pending purchases, certificates, opt-in revision and authenticated peers.

Deliver optional countersigned proofs on existing DM/group/channel paths, without
requiring text or changing text-message ratchets. Verify actual conversation author,
delegated account, pinned issuer and expiry locally. A single shared Flutter badge
reads this owner. The global visibility setting starts off. Legacy public author
labels alone cannot establish paid identity.
Native offer/participant snapshots carry verification provenance into every user
surface. A purchase makes its installation ineligible to adopt another account;
fresh linking before purchase rebinds the PLUS owner to the adopted account.

## Consequences

Server downtime cannot invalidate an issued certificate. A crash/retry does not
change the request, expiry or issuance. Blinding avoids a direct wallet/account
join at billing, with limited privacy in small issuance cohorts. Previously shared
proof cannot be erased from recipients. This pilot requires explicit devnet wallet
configuration; it adds no mainnet purchases, renewals before expiry, reinstall
recovery or entitlement synchronization. Real wallet/desktop acceptance remains a
separate manual gate. See [feature and protocol guide](../Features/plus-devnet.md).
