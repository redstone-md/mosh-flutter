# Production Mosh+ acceptance builds — 2026-10-20

> Compact checkout installers from `7d2cad69` are withdrawn after an installed
> Windows report: a PageStorage collision replaces the card with an error surface.
> The configuration-only `06e3aff9` installers below do not contain that disclosure.
> Replacement compact installers are tracked on [PR #91](https://github.com/redstone-md/mosh-flutter/pull/91).

The configuration fix is built and verified on Windows and universal macOS.
These replace the [withdrawn first installers](plus-mainnet-builds-2026-10-19.md).
The operator installed the corrected Windows build and confirmed that the Mosh+
card is visible. Its screenshot shows the mainnet price, recovery and paused sales.
The subsequent compact checkout refinement failed installed acceptance; see below.
Version remains **0.23.0**; identify artifacts by source commit and checksum.
No artifact has been attached to the existing GitHub release. Sales remain paused;
actual mainnet payments and wallet recovery await separately approved acceptance.

## Corrected configuration installers

Source: `feat/plus-mainnet`, commit
`06e3aff9af10da71dedbc62c2cfd8e6fda91511b`.
Each artifact contains its installer, `.sha256` and `plus-build.json`.

| Platform | Artifact | Installer SHA-256 |
| --- | --- | --- |
| Windows x64 | [mosh-0.23.0-setup.exe](https://github.com/redstone-md/mosh-flutter/actions/runs/39339967659/artifacts/12229662513) | `5b86b641f7c09afa51fe3132eeb241d923bec0f109e63720ef746286602dbf4c` |
| macOS Intel + Apple Silicon | [Mosh_0.23.0_universal.dmg](https://github.com/redstone-md/mosh-flutter/actions/runs/39339970360/artifacts/12230456222) | `e79e0c878c3c6ab6a53055cbaf13a57fce9832d031bb0da1e10483c0d277d048` |

Both packaging runs and the [source CI](https://github.com/redstone-md/mosh-flutter/actions/runs/39339940911)
passed. Downloaded archive digests and installer hashes matched GitHub and the
bundled sidecars. Manifests matched the independent expected configuration.
Windows native chrome/icon/call-window checks passed. macOS packaging checked
both architectures in all five native binaries and completed self-signed packaging.
An installed macOS launch has not been confirmed.

## Compact checkout refinement

Source: `7d2cad690bffbf71404c985b33203a4bddf288a7` on the same branch.
Price/currency and compact purchase/recovery actions stay visible. Mint, recipient,
full payment/privacy information and terms/support links move into **Payment details
& terms**. Sales pauses display **Purchases paused** instead of implying a broken
build. Recovery stays available when the catalog fails to load.

The [Windows build](https://github.com/redstone-md/mosh-flutter/actions/runs/39345042617)
and [universal macOS build](https://github.com/redstone-md/mosh-flutter/actions/runs/39345045861)
passed packaging and downloaded checksum/manifest verification, but are withdrawn.
The operator's Windows screenshot and TypeError exposed a missing storage boundary:
the disclosure read the profile's saved scroll offset as a boolean. Selectable
mint/recipient fields could then read the expansion flag as a scroll offset.
The fix gives expansion and both selectable fields independent PageStorage keys.
A regression mounts the real profile settings with delayed catalog loading after
scrolling, then expands the details and remounts the profile. It reproduced the
reported exception before the fix and checks that both expansion and scroll position
restore afterwards. This supplements the earlier isolated card previews.
Current PR checks are listed on [PR #91](https://github.com/redstone-md/mosh-flutter/pull/91).
Locally, Flutter analyze, 26 existing PLUS tests and five configuration
checks passed. Actual Flutter renders were inspected in English/Russian, narrow
layout, active membership, expanded details and catalog failure. Preview fixtures
do not establish real payment acceptance.

## Runtime configuration regression

The devnet provider constructed `const PlusConfig`. Adding mainnet selection
removed that outer constant context, leaving two non-constant
`String.fromEnvironment` calls. In AOT code they returned an empty issuer and
billing origin, so the card's `config.enabled` gate hid Mosh+. A saved devnet
certificate does not control that gate.

`PlusConfig.fromEnvironment()` now reads both values explicitly as constants.
Before writing a build manifest, packaging compiles and runs this same factory
with the requested defines, then compares actual issuer, origin, network and
enabled flags against the inputs. The regression failed before the fix and passed
afterwards. Ordinary proof builds without an issuer remain disabled.

Expected manifests identify `solana-mainnet`, `https://billing.mosh.run`,
`verification_enabled: true`, `purchases_configured: true`, the actual source
commit, and issuer key ID
`7b2cd6c2ba079c22f765276d5ed910fd57f75528113b5d721d75ba4eb748827f`.
The live issuer was checked against the independently stored public SPKI.
`purchases_configured` describes the client; the live catalog keeps sales disabled.

## Installation

Fully quit Mosh before installing: use the system-tray menu on Windows or Quit on
macOS. Install over the existing application. Open **Settings → Profile** and
scroll below the display-name form to **Mosh+**. No account reset or deletion of
the devnet certificate is needed.
