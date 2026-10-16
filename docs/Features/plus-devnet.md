# Mosh+ devnet pilot

Issue [#70](https://github.com/redstone-md/mosh-flutter/issues/70) implements one
30-day product purchased with nine-decimal classic SPL **test tokens** on Solana
devnet. Payment uses an external mobile wallet and a desktop Solana Pay QR.
The wallet keeps its keys. Mosh never signs a wallet transaction.

## Build and checkout

Configure both purchasing desktop clients explicitly:

```sh
flutter run --dart-define=MOSH_PLUS_SERVER_URL=https://billing.example \
  --dart-define=MOSH_PLUS_ISSUER_KEY=BASE64_SPKI_PUBLIC_KEY
```

The issuer key is an independent trust pin. A catalog response cannot replace it.
Without a pin the pilot is disabled; a pin without a server enables local badge
verification only. HTTP is allowed only on loopback. Keep the private issuer
implementation in the separate `mosh-billing` repository. Its README describes
key generation, durable SQLite storage and server configuration. Nothing in this
slice creates a remote repository, deploys a server or uses mainnet.

Profile settings displays price, mint, recipient, devnet, term and network-fee
notice before creating an order. The encrypted native owner saves the immutable
order and its bearer capability before the QR appears. The standard QR does not
select a Solana cluster: switch the mobile wallet to **Devnet** before scanning,
and fund it with the configured test token and devnet SOL for fees. Provision
the recipient's associated token account before accepting payments.

The native order, blinding inverse and certificate survive closing Mosh. Polling
resumes an outstanding order when the configured app is running. Failed reads or
issuance retain the last snapshot and expose Retry. A completed certificate needs
no payment server to remain valid. Orders cannot be replaced while pending or
active; a completed or interrupted issuance can be replaced after its expiry.

## Protocol and ownership

`GET /v1/catalog` returns `network=solana-devnet`, `product=mosh-plus-30d`, `mint`,
`recipient`, `amount_atomic` (canonical positive u64 string), `token_decimals=9`
and `issuer_public_key_b64` (SPKI DER, standard base64). The client compares the
key with its build pin. All price formatting and comparisons use integer units.

`POST /v1/orders` returns an immutable quote with random `id`, `reference`,
`payment_uri`, `status=awaiting_payment` and an `access_token`. Subsequent
`GET /v1/orders/:id`, `POST .../refresh` and `POST .../issue` require
`Authorization: Bearer <access_token>`. Capabilities never go into URLs or logs.

Refresh independently verifies the devnet genesis, successful finalized transfer,
classic token program, reference, mint, recipient and exact integer received
amount. A submitted transaction signature or wallet callback grants nothing.
Overpayment and late correct payment are accepted; partial transfers are not
combined. The server durably claims a transaction for one order only.

The first verified paid transition reserves the durable issuance intent and
`expires_at_ms`: thirty days from that transition, rounded **up** to a UTC day.
The client persists its blinding state before submitting
`{"blinded_message_b64":"..."}` to `POST .../issue`. The server binds the first
valid request before signing and persists `blind_signature_b64` before replying.
Retries/concurrent calls/restarts retain the same request, expiry and result.

Use RSAPBSSA-SHA384-PSS-Deterministic, with safe-prime RSA issuer keys of
2048–4096 bits. This is the partially blind protocol from draft-amjad-cfrg-
partially-blind-rsa-02; RFC 9474 alone does not define this metadata extension.
The `Deterministic` name describes message preparation; PSS still uses its salt.
The hidden subject is UTF-8 `mosh-plus-subject-v1\0<account_id>`; public metadata
is UTF-8 `mosh-plus-devnet-v1\0mosh-plus-30d\0<expires_at_ms>` (decimal millis).
Account IDs are the existing lowercase 64-hex linked-account root, not a Moss
identity or an MLS leaf. Neither order ID nor wallet appears in certificate claims.

The public [interop vector](../../mosh-core/tests/fixtures/plus-public-vector.json)
was issued by TypeScript, finalized by Rust and verified by Go CIRCL. The separate
IETF test-key fixture is a **published test key**, never an operational issuer.
Partially blind issuance hides the Mosh account from billing; small cohorts and
network/timing observation still limit unlinkability. Do not promise anonymity.

## Badge delivery

One visibility switch is initially off. The shared badge reads native-verified
evidence for own profile, DM header/details/list/offer, message authors,
participants and organization member/offer identities. Group/channel titles
represent conversations and receive no paid user badge. Legacy public messages
without a native-verified origin cannot borrow a badge by claiming a fingerprint.

`plus::PlusRuntime` owns encrypted local purchase, visibility revision and peer
evidence in additive `plus_records` storage. Runtime account proofs delegate the
linked account to the actual conversation author; that author countersigns the
context, proof, certificate and monotonic revision. DM additionally matches its
authenticated membership/account map. Groups reuse their verified sender carrier;
channels verify their real Moss author signature. Aliases come from those carriers.

Optional proofs travel every five seconds, including without text messages.
DM/group proofs use the existing MLS exporter with a separate domain, AES-GCM
and context AAD; they do not advance ordinary application-message ratchets.
Channel proofs are public like the channel itself. Receivers verify pinned issuer,
account ownership, context, signature, expiry and revision locally. Evidence is
bounded (2048 accounts, 128 aliases/account); unchanged verified certificates do
not repeat RSA verification or persistence on every advertisement. Restart checks
cached certificates against the current pin. Conversation owners acquire the PLUS
lock; the PLUS owner never acquires a conversation lock.

Opt-out publishes a higher signed revision. Recipients reject older revisions;
expiry is evaluated locally even offline. Opt-out cannot erase previously shared
proof from another person's copies. Linked-device entitlement sync, recovery after
reinstall, early renewal, other durations and service grace are deferred.

## Verification and acceptance

- HTTP tests in the private repository use durable SQLite, real partially blind
  crypto and SDK-encoded/signed transfers through a local RPC fixture. They check
  unsuccessful/unfinalized/wrong-token/wrong-recipient/underpaid transfers,
  overpayment, ambiguous references, durable retry and concurrent issuance.
- `node scripts/moss-test.mjs --test plus_certificate --test plus_purchase`
  checks native certificates, encrypted restart, opt-out, forgery, pin changes and
  replacement after an expired issuance.
- `node scripts/moss-test.mjs --test multi_device_dm_flow plus_flow::verified_plus`
  uses independent installations, real Moss and MLS, and no text messages to
  deliver then hide the badge across DM, group and channel.
- After `cargo build --manifest-path mosh-core/Cargo.toml`,
  `flutter test native_test/plus_commands_test.dart` uses the actual bridge.
- `flutter test test/features/plus` covers HTTP access, trust pin, exact price,
  durable QR before payment, retry, opt-in, legacy identity protection and narrow
  Russian layout. A rendered QR is decoded through the existing image importer.

Automated RPC fixtures are not a real-chain/mobile-wallet acceptance result.
The remaining manual gate requires an HTTPS pilot server, a devnet mint/treasury,
funded external mobile wallet and two Windows/macOS clients. Pay a QR, restart the
verifier during pending issuance, restart the buyer, then check the same expiry,
default hidden state, explicit opt-in in all user surfaces and opt-out. Repeat an
underpayment without granting access. Record wallet/OS/build/mint/transaction
signature and outcomes privately; do not publish order capabilities or keys.

The existing conversation widget builders/control dispatchers retain documented
size exceptions. PLUS peer authorization and the scenario tests keep complete
verification/persistence sequences together; these functions may exceed 50 lines.
Generated bridge files are not handwritten code.
