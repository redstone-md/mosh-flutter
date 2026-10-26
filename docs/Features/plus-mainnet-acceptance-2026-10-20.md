# Production Mosh+ acceptance — 2026-10-20

## Decision and scope

The owner accepted the production Mosh+ slice on 2026-10-20 and authorized closing
[issue #70](https://github.com/redstone-md/mosh-flutter/issues/70):
“можем фиксировать и закрывать приемку mosh+”. This records the owner's product
acceptance, alongside the previously recorded automated and release evidence.

The accepted slice provides a locally verified supporter badge for 30 days,
one-time Solana mainnet purchases for **5 USDC** or **2,575 CLXAI**, renewal,
linked-device purchase/visibility synchronization and wallet recovery. Badge
verification covers DMs, groups, channels and identity surfaces. Devnet purchases
remain separate from production entitlements.

## Release and evidence

- [Mosh 0.24.1](https://github.com/redstone-md/mosh-flutter/releases/tag/v0.24.1)
  ships Windows x64, universal macOS and signed Android ARM64 installers from
  `6f73fcc18fe43e3fecf9e945e9863fc66af69ac1`.
- Release CI completed successfully. Downloaded installer checksums, Android
  signing/package checks and matching production `plus-build.json` manifests were
  verified. Public release asset digests matched the independently checked files.
- The owner enabled production sales at `https://billing.mosh.run` on 2026-10-20.
  The live catalog was checked with purchases enabled and the configured issuer,
  recipient, prices and public terms intact.
- Automated payment, renewal, recovery, persistence, signature interoperability
  and real-Moss peer/device checks are described in the
  [feature guide](plus-mainnet.md#evidence-and-acceptance).

This update adds the owner's acceptance decision. It adds no transaction receipts,
individual hardware test results or deployed signer CPU measurements.

## Follow-up boundaries

Measuring deployed signing CPU against Workers Free limits remains an operational
check, not a result established by this acceptance record. Preserve the issuer
and the ability to fulfill or recover already paid orders during any sales pause.

Paid relay, mailbox, storage and names remain later product slices. Android
background incoming calls and idle battery/network optimization are tracked
together in [issue #94](https://github.com/redstone-md/mosh-flutter/issues/94),
including the reported desktop idle traffic. Their completion is independent of
Mosh+ acceptance.
