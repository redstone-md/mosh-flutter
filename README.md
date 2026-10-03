<h1 align="center">Mosh</h1>

<p align="center">
  A desktop-first messenger with private conversations over a peer-to-peer network.
</p>

<p align="center">
  <a href="https://github.com/redstone-md/mosh-flutter/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/redstone-md/mosh-flutter?style=flat-square&color=B7D84A&labelColor=161819"></a>
  <a href="https://github.com/redstone-md/mosh-flutter/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/redstone-md/mosh-flutter/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="License: GPL v3" src="https://img.shields.io/badge/license-GPL_v3-B7D84A?style=flat-square&labelColor=161819"></a>
</p>

<p align="center">
  <a href="https://github.com/redstone-md/mosh-flutter/releases/latest">Download</a> ·
  <a href="CHANGELOG.md">What's new</a> ·
  <a href="docs/Architecture.md">Architecture</a> ·
  <a href="https://github.com/redstone-md/mosh-flutter/issues">Report a bug</a>
</p>

![Mosh desktop showing a fictional conversation with Maya, a file, a voice note and conversation details](docs/assets/chat-desktop.png)

<p align="center"><sub>Actual Flutter interface with fictional messages and simulated connection states. No personal conversation data.</sub></p>

## Download

Choose your build from the [latest release](https://github.com/redstone-md/mosh-flutter/releases/latest).
Every download has a SHA-256 checksum alongside it.

| Platform | Download | Installation |
| --- | --- | --- |
| Windows x64 | `mosh-<version>-setup.exe` | Run the installer. Installs for your user without an admin prompt and upgrades in place. |
| macOS 12+ | `Mosh_<version>_universal.dmg` | Apple Silicon and Intel. Open the image and drag Mosh to Applications. |

Android also supports linked text chats while the app is in the foreground.
Published downloads currently cover Windows and macOS.

<details>
<summary>First-launch warnings and download verification</summary>

Mosh currently ships without a signature trusted by Windows or macOS. The
macOS app has a self-signed signature and is not notarized. See the
[signing policy](CODE_SIGNING.md).

- Windows SmartScreen: choose **More info**, then **Run anyway**.
- macOS Gatekeeper: try opening the app once, then go to
  **System Settings > Privacy & Security > Open Anyway**.

On Windows, compare this output with the matching `.sha256` file:

```powershell
Get-FileHash .\mosh-*-setup.exe -Algorithm SHA256
```

On macOS, put the DMG and its checksum in the same directory, then run:

```sh
shasum -a 256 -c Mosh_*_universal.dmg.sha256
```

</details>

## Inside Mosh

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/assets/mesh-conversations.png" alt="Glass conversation bubbles connected through a peer mesh" width="420">
      <h3>Private conversations over a mesh</h3>
      <p>Private chats and groups use OpenMLS end-to-end encryption. Moss finds peers automatically, with no central message server or hostnames to enter.</p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/assets/linked-devices.png" alt="A glass laptop and phone connected by a lime-lit path" width="420">
      <h3>Continue on another device</h3>
      <p>Link with a QR and confirmation code. Continue text DMs and recover available history. Each installation keeps its own keys and encrypted local storage.</p>
    </td>
  </tr>
</table>

- Share files, send voice notes and make encrypted one-to-one voice calls.
- Search personal chats, groups and channels in one list, with conversation
  details beside the chat on wide windows.
- Set up your name, devices and network preferences once. Saved progress
  resumes after restart, and Settings keeps these choices accessible.
- Use the desktop sidebar or the compact phone layout, in English or Russian.

## Start a conversation

1. Open Mosh and choose a display name. Keep networking automatic unless you
   need to route Mosh around a VPN.
2. Choose **This is my first device**, or link an existing profile using the
   trusted device's QR or private link and confirm the code on that device.
3. Start a conversation and share its invitation with your contact. They open
   it in Mosh to join.

Your name, devices and network preferences remain available in Settings.
Existing installations with conversations or linked devices skip the setup
wizard. Incoming conversation invitations wait until setup finishes.

[First-run guide](docs/Features/first-run-setup.md) ·
[Device linking](docs/Features/device-linking.md) ·
[Private chats](docs/Features/private-dm.md)

## Privacy you can inspect

Private chats and groups are end-to-end encrypted. Public channels are signed
and are not confidential. Peer discovery uses public trackers, so content
encryption does not make network activity anonymous. Participants can see
device associations.

Message history is encrypted locally. Crash reporting is off by default and
can be enabled in Privacy settings.

<details>
<summary>How local history keys are stored</summary>

Windows and Linux use the OS credential store for the history key; Android
uses Keystore. On macOS, the key is kept in
a permission-restricted file in the app container. These choices and their
limits are documented in the
[storage and threat model](docs/ADR/0011-secure-storage-and-threat-model.md).

</details>

## Development

The app is Flutter and Riverpod over a Rust core, connected by
`flutter_rust_bridge`. The core owns OpenMLS, Moss transport, persistence and
voice calls.

<details>
<summary>Build from source and repository map</summary>

Use the toolchain versions from [.github/actions/setup](.github/actions/setup/action.yml)
and [rust-toolchain.toml](rust-toolchain.toml). You also need Node.js and the
native build tools for your platform. Start on Windows or macOS:

```sh
git clone --recursive https://github.com/redstone-md/mosh-flutter.git
cd mosh-flutter
node scripts/moss-prepare.mjs
flutter pub get
```

On macOS, prepare the native audio library before the first build:

```sh
brew install autoconf automake libtool
bash scripts/opus-prepare-macos.sh
```

Then run `flutter run -d windows` or `flutter run -d macos` on the matching
platform. Moss is built from the pinned submodule, including both macOS
architectures.

| Location | Responsibility |
| --- | --- |
| `lib/` | Flutter UI, feature state and generated Dart bindings |
| `mosh-core/` | Rust runtime, encryption, transport and local persistence |
| `moss/` | Pinned Go transport submodule |
| `docs/ADR/` | Architecture decisions |
| `test/support/` | Scripted dependencies shared by widget tests and previews |

See [AGENTS.md](AGENTS.md) for checks and contribution constraints, and the
[architecture map](docs/Architecture.md) for runtime boundaries.
The [visual asset notes](docs/assets/README.md) explain how to regenerate the
README screenshot and record the illustration prompt.

</details>

## License

[GNU GPL v3](LICENSE). Bundled Inter fonts use the
[SIL Open Font License](assets/fonts/Inter-OFL.txt).
