# Licenses

Mosh is GPL-3.0-or-later. [LICENSE](../LICENSE) adds a section 7 permission to
publish it through app stores whose terms restrict recipients (the App Store,
the Mac App Store, Google Play, the Microsoft Store, RuStore), provided the
source stays available. The permission covers only code the copyright holders
own: ForeverInLaw and Rxflex, and contributions under [CLA.md](../CLA.md). So
a store build must not contain third-party code under the GPL or AGPL, which
cannot carry that permission. This page records the audit of the shipped tree
(MOSH-73, 2026-11-06) and the decision for each component that needed one.

## What CI checks

The `Dependency licenses` job in [ci.yml](../.github/workflows/ci.yml) fails
when a shipped dependency brings a license outside these lists:

- **Rust:** `cargo deny check licenses` with [deny.toml](../deny.toml) for
  `mosh-core`, `mosh-media/webrtc` and `mosh-media/capture`, dev dependencies
  excluded and all features on.
- **Dart and Go:** [license-check.mjs](../scripts/license-check.mjs) reads
  every license file of each non-dev Dart package outside the Flutter SDK and
  of each Go module in Moss's `cmd/moss-ffi`. GPL, LGPL and AGPL texts,
  missing files and unrecognised texts fail unless `REVIEWED` names that
  package version.
- **libwebrtc:** [libwebrtc-build.mjs](../scripts/libwebrtc-build.mjs) refuses
  to package a build whose generated `LICENSE.md` contains a GPL-family
  component, ffmpeg, openh264 or x264.

An addition to `REVIEWED` or `deny.toml` needs a row below. Native libraries
that Flutter plugins download (libmpv for media_kit) are outside these
checks: review the row below when a `media_kit_libs_*` version moves in
pubspec.lock.

## Shipped components

| Component | License | Decision |
| --- | --- | --- |
| Mosh (`lib/`, `mosh-core`, `mosh-media`) | GPL-3.0-or-later + store permission | Ours. |
| Moss | MIT | Ours. |
| Rust crates of `mosh-core`, the libwebrtc engine and the camera helper | MIT, MIT-0, Apache-2.0 (also WITH LLVM-exception), 0BSD, BSD-1/2/3-Clause, ISC, Zlib, zlib-acknowledgement, Unicode-3.0, BSL-1.0, Unlicense, CC0-1.0 | Permissive. |
| `hpke-rs` and its backends | MPL-2.0 | File-level copyleft, compatible with the GPL and the stores; its source is public and unmodified. |
| `mozjpeg` (camera helper, desktop) | IJG | Needs the IJG acknowledgement, now in [THIRD_PARTY_NOTICES](../mosh-media/THIRD_PARTY_NOTICES.md). |
| `r-efi` | MIT OR Apache-2.0 OR LGPL-2.1+ | Used under MIT or Apache-2.0. |
| `webrtc-sys`, `libwebrtc` crates | Apache-2.0 | Permissive; patches in `third_party/*-patches`. |
| libwebrtc (LiveKit's webrtc-sdk fork) | BSD-3-Clause with BSD, ISC, Apache-2.0 and zlib components | Built with `rtc_use_h264=false`: no ffmpeg or openh264. H.264 and H.265 come from the platform encoders. |
| nokhwa | Apache-2.0 | Permissive. |
| Dart packages | BSD-3-Clause, MIT, Apache-2.0, BSD-2-Clause | Permissive. |
| `dbus`, `gtk` (Dart, Linux only) | MPL-2.0 | Compatible; not in Apple builds. |
| Go modules of Moss | BSD, MIT, Apache-2.0, ISC, MPL-2.0 (anacrolix) | Permissive or file-level copyleft. |
| `anacrolix/multiless`, `anacrolix/sync` | MPL-2.0 upstream, no file in the pinned versions | In `REVIEWED`; MOSH-79 moves Moss to versions with the file. |
| libmpv and ffmpeg (media_kit) | LGPL-2.1-or-later; LGPL-3.0 on Windows | Kept, linked dynamically (frameworks on Apple), as VLC ships libVLC on the App Store under the LGPL. Apple and Android use the `default` builds of media-kit's libmpv-darwin-build and libmpv-android-video-build, made for playback without GPL parts; the Windows build configures ffmpeg with `--disable-gpl --enable-version3` and mpv with `-Dgpl=false`. MOSH-78 bundles the LGPL text and source links. |
| Flutter engine and SDK packages | BSD-3-Clause and bundled components | Flutter bundles their notices in every build. |
| Inter | SIL Open Font License 1.1 | Permissive for embedding. |
| RingRTC call engine (`mosh-media/engine`) | AGPL-3.0-only | Not checked, and outside the store permission. It is still the default engine, so the Microsoft Store MSIX and the RuStore APK ship it under its own AGPL terms. Apple store builds must use `MOSH_CALL_ENGINE=webrtc`. MOSH-76 makes libwebrtc the only engine and removes the AGPL mentions from the README, the media notices and CLA §4. |

## Notices

Flutter puts the license files of Dart packages into every build. The
desktop and Android packages carry the call media notices
(`mosh-media/THIRD_PARTY_NOTICES.md`, GPL-3.0.txt, Apache-2.0.txt and
WEBRTC-LICENSE.md). Rust crates, Go modules and libmpv have no notice inside
the app yet: MOSH-78 adds them to the in-app license list.
