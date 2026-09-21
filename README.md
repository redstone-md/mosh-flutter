# Mosh

Mosh is a desktop-first, decentralized, end-to-end-encrypted messenger. The
UI is Flutter; everything that must be right (OpenMLS, transport, storage,
calls) lives in one Rust core, `mosh-core`, reached through
`flutter_rust_bridge`. Peers find each other over the Moss mesh runtime; there
is no central server.

## Download

Windows installers and the macOS disk image are published on the
[**Releases**](https://github.com/redstone-md/mosh-flutter/releases) page,
each with a SHA-256 checksum. The Windows installer is per-user (no admin
prompt) and upgrades in place; message history is kept. The macOS DMG is a
universal binary (Apple Silicon + Intel) — drag the app to Applications.

Mosh ships unsigned (see [`CODE_SIGNING.md`](CODE_SIGNING.md)); both
platforms warn on first run.

- **Windows** — SmartScreen: **More info**, then **Run anyway**.
- **macOS (12 Monterey or later)** — Gatekeeper blocks the first launch:
  try to open the app once, then **System Settings → Privacy & Security →
  Security → Open Anyway** (the button appears for about an hour after
  the blocked attempt; enter your login password). This is Apple's
  documented flow. On macOS 14 and older the right-click → **Open**
  shortcut also works. The terminal equivalent is
  `xattr -dr com.apple.quarantine /Applications/mosh.app`.

## Features

- **Private 1:1 DMs** — invite-URI onboarding with out-of-band fingerprint
  confirmation.
- **Channels and private groups** — multi-party conversations with their own
  membership and per-conversation DMs.
- **Attachments and voice messages** — chunked, encrypted file transfer with
  thumbnails, a media viewer and inline voice playback.
- **Voice calls** — encrypted real-time audio with jitter buffering.
- **End-to-end encryption** — OpenMLS group messaging over every channel.
- **Decentralized discovery** — Moss mesh-based peer discovery; users never
  enter hosts or ports in the primary flow.
- **Encrypted persistent history** — conversations and MLS session state
  survive restarts; the key is unlocked by user presence.
- **English and Russian** UI.

## Architecture

- `lib/` — the Flutter app. Features under `lib/src/features/`, Riverpod
  state under `lib/src/state/`, the generated bridge under `lib/src/rust/`.
- `mosh-core/` — the Rust core: runtimes, adapters, crypto, the `api/` facade
  the bridge exposes.
- `moss/` — the Moss transport, a git submodule of `redstone-md/moss` built
  from Go into a shared library the core loads at runtime.
- `docs/adr/` — the decisions, numbered.

## Getting started

```powershell
git clone --recursive https://github.com/redstone-md/mosh-flutter
cd mosh-flutter
node scripts/moss-prepare.mjs      # builds the Moss library (needs Go;
                                    # on macOS it is universal, arm64+x86_64)
flutter pub get
flutter run -d windows              # or: flutter run -d macos
```

Rust (see `rust-toolchain.toml`), Go and Flutter are required. `AGENTS.md`
lists every build, test and packaging command.

## Persistence and privacy

Message history and MLS state are encrypted at rest with a key held in the OS
credential store. Uninstalling removes the app, not the history: a reinstall
picks it back up. See ADR 0011 for the threat model.

## Release notes

See [`CHANGELOG.md`](CHANGELOG.md). Each GitHub release carries the changelog
section for its version and the commits it contains.

## License

See [`LICENSE`](LICENSE).
