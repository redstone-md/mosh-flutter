# Issue 70: Mosh+ devnet purchase and verified badge

Status: product scope, implementation contracts, dependencies, additive schemas
and TDD seams approved by the user in the implementation interview.

Issue: https://github.com/redstone-md/mosh-flutter/issues/70
Starting revision: `10e4a711808a66f6592831516ce33648fbaae8b3`.

## Approved behavior

- One Mosh+ product, priced in a configured integer amount of classic SPL test
  tokens on Solana devnet. No production CLXAI mint or real funds in this pilot.
- Desktop checkout shows the product, amount, token mint, recipient, network,
  validity, wallet network-fee notice and Solana Pay QR. The external mobile
  wallet retains all wallet keys. Standard transfer QR does not select devnet;
  explain the wallet's required devnet setting.
- The payment server independently verifies a successful finalized transfer,
  reference, mint, recipient and integer amount. A callback/signature is only
  a hint. A transaction cannot fulfill two orders. Overpayments and late correct
  payments are accepted; underpayments are not combined or granted access.
- Orders and issuance survive server restart. Retries and concurrent requests
  return the same issuance for an order; they cannot extend its original term
  or switch its blinded request. Persist client blinding state before sending it.
- Thirty days start at first durably recorded issuance; round expiry upwards
  to a shared UTC day boundary. No order ID, wallet, precise purchase timestamp
  or other unique order metadata in the public certificate claims.
- Partially blind issuance hides the existing account identity from the server.
  The certificate belongs to the linked account, not one conversation or device.
  Small issuance cohorts still limit unlinkability; do not promise anonymity.
- The purchasing desktop saves the certificate in encrypted native storage.
  Closing/restarting the client preserves pending work and the completed result.
- One visibility switch, initially off, applies everywhere. Display one shared
  verified badge wherever an existing surface represents a user: own profile,
  DM header/details/list entry/offer, message authors and participant lists.
  Group/channel titles represent conversations and do not acquire a user badge.
- Recipients verify issuer signature, expiry, devnet domain and authenticated
  account ownership locally. Unknown, forged, expired or mismatched evidence
  cannot produce a badge. Server availability does not affect valid certificates.
- Existing conversations and ordinary messaging remain compatible. Missing
  optional PLUS proofs remain ordinary users, including legacy messages.

## Deferred work

Mainnet, real prices, USDC, handles, paid relay/mailbox/storage, translation,
recovery after reinstall, entitlement sync to linked devices, early renewal,
three/twelve-month products and seven-day service grace are separate slices.
After expiry the same product can be bought again. Previously disclosed payment
status cannot be erased from other people's copies by changing visibility.

## Module and repository ownership

- `mosh-flutter` owns the public protocol, native certificate/purchase owner,
  encrypted client persistence, adapters, shared badge and checkout UI.
- The closed payment implementation belongs to a separate local Git repository
  at `/root/private/mosh-billing`; never add its source to this public repository
  or modify sibling repositories. Remote creation, publication and deployment
  require a concrete reviewed result and separate approval.
- The server is one Node/TypeScript process: Hono HTTP endpoints, durable SQLite
  orders/unique transaction claims and a read-only Solana verifier. Its issuer
  signing key is separate from treasury keys; no treasury private key is needed.
- Use existing Riverpod, native bridge, encrypted redb, device/account proofs,
  authenticated conversation control paths, QR and Dart HTTP facilities.
- Keep server location and issuer trust explicit pilot configuration. Pin the
  issuer trust key independently of responses from the payment endpoint. Use
  HTTPS outside loopback; reject mainnet configuration in this devnet slice.

## Proposed additions requiring confirmation

- Rust dependency: `blind-rsa-signatures` for partially blind RSA. Check exact
  version, safe-prime key requirements and shared suite interoperability first.
- Private server dependencies: Hono, its Node adapter, `@cloudflare/blindrsa-ts`,
  current `@solana/pay` and its required Solana Kit/token packages. Use Node's
  SQLite and test runner; TypeScript and Node types provide static checking.
  Flutter needs no new packages.
- Add feature-local PLUS bridge commands/snapshots for durable purchase state,
  preparing/finalizing issuance and visibility. Private keys and blinding
  secrets never cross the bridge; blinded requests are safe to send to issuer.
- Add versioned encrypted local purchase/entitlement and peer evidence records.
  Changes are additive, without rewriting existing conversation history.
- Add optional authenticated PLUS control/proof delivery to DM/group/channel
  owners, reusing existing account delegation and identity binding. PLUS
  updates must work without forcing the user to send a chat message.
- Share typed public wire examples/test vectors with the private server;
  publishing the issuer implementation is unnecessary for interoperability.

## Proposed TDD seams

1. Payment HTTP interface (`create order`, `read status`, `issue certificate`),
   using real durable SQLite and real protocol/cryptography dependencies.
   Catches payment validation, exactly-once issuance and restart behavior;
   does not prove mobile wallet UI behavior or native bridge integration.
2. Native PLUS/conversation public commands and snapshots with encrypted storage,
   actual signatures/MLS and independent native installations where required.
   Catches forgery, account mismatch, expiry, hidden state, peer propagation and
   recovery; does not prove Flutter layout or an external RPC's availability.
3. Flutter checkout/settings and existing user identity surfaces through
   `test/support` adapters. Catches caller-visible loading/error/retry, QR,
   opt-in and consistent badge behavior; native cryptography stays at seam 2.
4. One real devnet wallet payment plus two independent desktop clients and a
   verifier restart. Catches the deployed combination; requires a mobile wallet
   and desktop environments unavailable to a headless Linux test runner.

## Execution and checks

1. Confirm additions and seams; run existing preparation/baseline checks.
2. Prove TypeScript issuance -> Rust finalization/verification -> Go verification
   with common partially blind vectors. Do not substitute account-linked plain
   issuance if interoperability fails.
3. Grow one working tracer at a time: durable server order/payment -> native
   issuance/persistence -> authenticated peer badge -> checkout/shared surfaces.
4. Write one failing caller-visible test before each implementation increment.
   Run focused tests and static checks regularly; run full relevant suites once
   at the end. Target >=80% changed-line and >=70% branch coverage where available.
5. Run Rust build/fmt/tests/clippy; prepare Moss first. Regenerate bridge and
   verify binding drift. Run Flutter analyze/tests/format and server typecheck/
   tests. Document any unavailable real-device checks without claiming a pass.
6. Update architecture, feature docs and an ADR. Review standards and spec from
   the pinned starting revision, fix findings, and commit verified changes to
   the current branches as ForeverInLaw without attribution trailers.

## Risks to resolve with evidence

Partially blind implementations/suite compatibility; precise integer validation
with modern Solana SDKs; lost issuance state after a crash; duplicate transfer
claims; untrusted public channel identities; stale opt-out/revocation evidence;
bounded proof dissemination and mixed-client compatibility. Keep secrets, IP
addresses, QR/order bearer tokens and blinding state out of logs and commits.
