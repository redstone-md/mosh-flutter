# Production Mosh+ acceptance installers — 2026-10-19

**Withdrawn on 2026-10-20:** these installers hide Mosh+ because the issuer key
and billing origin were read without `const` and become empty in AOT code.
Matching sidecar manifests did not establish runtime configuration. Do not use
these artifacts for acceptance. [Corrected installers](plus-mainnet-builds-2026-10-20.md) passed with a
compiled configuration check before packaging; the hashes below are historical.

Prepared from `feat/plus-mainnet` commit
`de4b0d6f01ebfb8f3703f9a9e667da8a6988df9f`, version **0.23.0**.
These feature-branch acceptance artifacts have not been attached to a release.
The existing `v0.23.0` release was built earlier; identify these artifacts by
their manifest commit as well as their checksums.
Billing sales remain paused. Real mainnet payment and phone-wallet recovery
acceptance are still pending; follow the [Russian guide](plus-mainnet-ru.md).

## Downloads and checksums

Each GitHub artifact contains the installer, its `.sha256` and `plus-build.json`.

| Platform | Artifact | Installer SHA-256 |
| --- | --- | --- |
| Windows x64 | [mosh-0.23.0-setup.exe](https://github.com/redstone-md/mosh-flutter/actions/runs/39331977759/artifacts/12227000315) | `8b5ca261c455032cb60d174c7049b7433af3c98fa2b343a819d4693e19984dcb` |
| macOS Intel + Apple Silicon | [Mosh_0.23.0_universal.dmg](https://github.com/redstone-md/mosh-flutter/actions/runs/39331980655/artifacts/12226333885) | `76c33e0153830aa1eb19d18c68a0d084b78ac3061e11f461b7a0e92f54c698c4` |

## Configuration and evidence

Both downloaded manifests matched these independently checked settings:

```json
{
  "version": 1,
  "commit": "de4b0d6f01ebfb8f3703f9a9e667da8a6988df9f",
  "network": "solana-mainnet",
  "verification_enabled": true,
  "purchases_configured": true,
  "billing_origin": "https://billing.mosh.run",
  "issuer_key_id": "7b2cd6c2ba079c22f765276d5ed910fd57f75528113b5d721d75ba4eb748827f"
}
```

Both builds used the committed release profile (`parallel-codegen=false`);
macOS used `universal=true`. Windows native chrome/icon/call-window checks passed.
macOS packaging passed its native architecture and deep code-signature checks.
Downloaded ZIP hashes matched GitHub's artifact digests, and installer hashes
matched their bundled sidecars. The full [client CI](https://github.com/redstone-md/mosh-flutter/actions/runs/39331654370)
also passed on this source commit.

Public repository variables `MOSH_PLUS_SERVER_URL` and `MOSH_PLUS_ISSUER_KEY` are
configured for the release workflow in this branch. The complete SPKI was checked
against the independent issuer record and live catalog before dispatch.
Ordinary PR proof artifacts without explicit PLUS inputs remain unconfigured.

`purchases_configured: true` records client configuration; the live catalog still
returns `purchases_enabled: false`. After installation, open **Settings → Profile**
and scroll to the **Mosh+** card below the display-name form. Check both asset prices
(5 USDC / 2575 CLXAI) and the purchase-terms/support links. The disabled payment
button currently uses “Покупки недоступны в этой сборке.” while sales are paused.
Desktop launches and real payment/recovery flows were not verified on this Linux
host. Existing unsigned Windows and non-notarized macOS signing policies apply.
