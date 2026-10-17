# Issue 70: live devnet acceptance

Scope: prepare the private billing companion with the existing issuer pinned in
PR #89's installers, provision a nine-decimal classic SPL devnet mint and test
wallets, and exercise real payment through HTTP and the existing native commands.
Keep wallet seeds, order capabilities, SQLite and issuer material outside Git.

1. Prepare persistent private state and devnet funding. Verify the genesis before
   sending transactions; preserve the current issuer and installation data.
2. Start loopback billing with its permanent database. Compare its public key
   against the existing installer provenance.
3. Pay a Solana Pay request on devnet. Verify underpayment refusal, issuance,
   durable retries, client/server restarts and independent native peer badges.
4. Run the relevant existing checks. Record actual outcomes and publish an
   installation/test guide for the ready-built clients in this PR.

Risks: public faucet/RPC availability can block on-chain execution. Mobile-wallet
QR handling and Windows/macOS installer interaction still need those devices;
headless acceptance must not be described as their manual verification.

No mainnet transactions, new application dependencies, public deployment,
contract/schema changes, release or merge are included.
