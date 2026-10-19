# Production Mosh+

Mosh+ supports development and displays a verified badge in DMs, groups, channels
and identity surfaces. It does not buy relay capacity or alter free chat/call
features. Initial prices are **5 USDC** or **2,575 CLXAI** for 30 days on Solana
mainnet. External wallets approve each payment; there are no automatic charges.
Open **Settings → Profile** and scroll to the **Mosh+** card below the display-name
form for purchase, renewal and recovery.

Implementation is on `feat/plus-mainnet`. The devnet pilot is complete; production
activation and real mainnet acceptance are still pending. See the
[Russian walkthrough](plus-mainnet-ru.md), [approved plan](../Proposals/issue-70-plus-mainnet.plan.md)
and [ADR 0047](../ADR/0047-plus-production-periods-and-wallet-recovery.md).

## Ownership and contracts

| Boundary | Owner |
| --- | --- |
| Catalog, fixed quote, payment verification, renewal schedule, wallet consent | Private `mosh-billing`, `/v2` HTTP |
| Account subject, blind secrets, recovery destination key, certificates | Native `mosh-core/src/plus` |
| Account sync | Existing encrypted, authenticated device metadata stream |
| Purchase/recovery interaction | Feature-local Riverpod controller and billing client |
| Badge verification and display | Native proof verification and shared `UserPlusBadge` |

USDC uses mint `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`, six decimals
and 5,000,000 atomic units. CLXAI uses
`ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK`, nine decimals and
2,575,000,000,000 atomic units. Prices are canonical integer strings, never floats.
An operator price change affects new request IDs; native persists accepted terms
and the request ID before HTTP, so a lost response retains the original offer.

`GET /v2/catalog` declares network, product, issuer pin/key ID, recipient, assets,
prices, support, terms and the sales gate. `POST /v2/series` registers the native
random ID/capability idempotently. `POST /v2/orders` authenticates the series and
fixes a quote by request ID. Order read, refresh and issuance authenticate the
separate order capability. `GET /v2/series/:id` returns the reserved scheduling tail.
Capabilities belong in authorization headers or encrypted local state, never URLs.

Billing verifies finalized classic SPL transfers against reference, mint,
recipient ATA, exact instruction amount and actual received amount. Underpayments
are not summed; overpayment grants one normal period. A signature cannot fulfill
two orders. Ordinary signed source-owner transfers qualify automatically;
ambiguous/delegated sources and competing full payments enter durable manual
review. A scan lists up to 100 signatures and checks at most 32 transaction bodies
per refresh, preserving room under Workers Free's subrequest budget. It persists progress/candidate
before accepting a unique result across pages. Before allocation it checks the
history head again; new arrivals restart the scan without losing the candidate.
Later disputes need operator review.

Production partially blind public metadata is UTF-8:

```text
mosh-plus-mainnet-v1\0mosh-plus-supporter-30d\0<issuer_key_id>\0<valid_from_ms>\0<expires_at_ms>
```

The hidden subject remains `mosh-plus-subject-v1\0<account_id>`. First expiry is
durable verification time plus 30 days, rounded up to a UTC day. Renewals after
an unexpired tail append exactly 30 days. Future intervals cannot activate early.
Mainnet proof v2 includes independently versioned global visibility; old devnet
certificates cannot become production badges. Existing devnet records are retained.

## Linked devices and recovery

One account uses one renewal series. The original device initializes it and waits
for durable acknowledgement from the active roster before initial checkout. A
committed series syncs to later devices and survives revocation/restart. Conflicts
fail closed. An offline initializer/sibling can delay this initial gate. Prepared
issuance secrets sync so other devices can complete the same blinded request;
before that copy exists, issuance waits for its originating device.

Recovery starts a 15-minute session with a native-generated destination key and
separate polling capability. The public `/recover/:id` page shows the device code,
connects a wallet, verifies domain/URI/network/nonce-bound sign-in and requests
explicit consent for that wallet's original periods. Grants are paged in batches
of 32. Destination proof binds session, order and blinded request. A consumed
additional slot cannot be reused by another destination. Consent reserves its slot
and scheduling union atomically, preventing an exhausted order from moving a fresh
account's renewal tail. Retrying with the same destination/request is idempotent.

Restoring a purchase does not restore chats, identity or account keys. Existing
certificates keep their original expiry; there is no instant revocation. Recovery
and normal purchases preserve every original reserved interval, including periods
paid by another wallet that is not authorized in the current recovery session.

## Build and activation

Normal platform builders accept `plus-network`, `plus-server-url` and
`plus-issuer-key`. Use `solana-mainnet`; devnet requires an explicit network.
Release builds read public repository variables `MOSH_PLUS_SERVER_URL` and
`MOSH_PLUS_ISSUER_KEY`. No private key or treasury credentials enter Flutter or CI.
`scripts/plus-build-config.mjs` validates the origin and RSA public pin before
packaging and writes `plus-build.json` beside downloadable artifacts. It records
commit, network, enabled verification/purchase configuration and issuer key ID.
Mainnet artifacts keep ordinary names; only explicit devnet builds have a devnet
suffix. The macOS release installer remains universal (Intel and Apple Silicon).

The production origin and independently checked public pin were configured as
release repository variables on 2026-10-19. Separate Windows and universal macOS
[acceptance installers](plus-mainnet-builds-2026-10-19.md) were built and their
downloaded manifests and checksums verified. Ordinary PR proof artifacts without
explicit PLUS inputs remain unconfigured. Desktop acceptance is still pending.

Without a pin/URL, CI builds keep purchases disabled. With configured clients,
billing can still pause new sales independently. Pausing preserves existing order
refresh, issuance, recovery and local badge validation. Do not rotate an issuer
while existing paid/future/pending orders require it; a client trust and purchase
migration must precede such a change.

The selected deployment is Cloudflare Workers Free at `https://billing.mosh.run`,
with one SQLite-backed Durable Object keeping global payment uniqueness and atomic
recovery joins. It was deployed on 2026-10-19 with sales paused. HTTPS catalog,
independent issuer pin, recipient, assets/prices and secret bindings were verified;
the real RPC and both recipient ATAs passed read-only checks. The operator confirmed
Workers Free and an independent encrypted issuer backup. The private Workers
runbook records the deployed version, namespace, backup and rollback procedure.
The public [purchase terms](https://mosh.run/plus/terms) and updated
[privacy policy](https://mosh.run/privacy) were published on 2026-10-19;
both locales and support links passed live browser checks. Both public URLs were
applied to the live billing catalog and verified with sales still paused.
Installed-client and approved real mainnet acceptance remain activation gates.
Preflight checks genesis,
both mints/decimals, recipient token accounts and issuer continuity before sales.
The service never receives treasury signing keys. It rejects the published test
issuer when enabling sales.

The operator selected a separate ordinary treasury wallet with shared key custody.
Each key holder can spend independently; this wallet enforces no multisig approval
threshold. Revenue ownership must be agreed separately. Private support is
[@redstonemdbot](https://t.me/redstonemdbot); Sergey handles refund requests
through Evgeny, as confirmed by the operator and published in the purchase terms.

Automatic billing HTTP requests run only while Mosh+ settings are mounted and
there is pending work. Checks run every five seconds during the first minute,
then every thirty seconds, stopping after ten minutes. Reopening settings or a
manual check restarts the window; late payments and durable issuance remain
recoverable. The recovery panel also provides a manual status check, including
the remaining five minutes of its fifteen-minute session. A fresh visible card
registers its series before enabling purchase/recovery; idle accounts do not
register in the background. Local badge refresh continues independently without billing requests.
The renewal tail is fetched when unknown or advanced, rather than on every unpaid
poll. Workers/DO free quotas apply to the account, not each domain or Worker.

## Evidence and remaining acceptance

Automated checks cover HTTP payment/renewal/recovery with genuine SDK-signed
transactions over a fixture RPC, native restart/interval/account isolation,
TS→Rust→Go signature interoperability, rendered checkout/recovery QR decoding,
sales pause and durable checkout retry. Real Moss processes cover linked and
subsequently linked device metadata; production DM/group/channel proof delivery
uses the same authenticated carriers. Fixtures do not establish mainnet payments.

Before opening sales, record installer hashes and public build manifests, then
approve and perform actual mainnet payments in both assets to the configured recipient,
early renewal, linked-device transfer and recovery on a new account. Confirm the
mobile wallet browser's sign-in/consent on a real phone. A standard Solana Pay QR
does not select a cluster; use Solana mainnet and the phone's ordinary Camera if a
wallet's internal scanner treats the URI as an address. Keep the completed
[devnet pilot guide](plus-devnet-pilot-ru.md) as its historical acceptance record.
