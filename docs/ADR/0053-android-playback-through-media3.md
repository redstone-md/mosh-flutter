# ADR 0053: Android plays media through the system's media3, not libmpv

Date: 2026-11-11
Status: Accepted and implemented (MOSH-74). Desktop and iOS keep libmpv.

## Context

media_kit plays everything Mosh plays outside calls: video and audio attachments
in the viewer, voice messages, the recording preview in the voice composer. It
also takes the frame a video attachment's previews are made from
([ADR 0041](0041-attachment-previews.md)). On every platform it does that with
libmpv.

On Android `media_kit_libs_android_video` downloads a prebuilt libmpv from a
GitHub release while Gradle configures the build. F-Droid's main catalog rebuilds
an app from source and does not accept that (MOSH-59).

That libmpv is also old. media-kit's build scripts pin ffmpeg 6.0 and libxml2
2.10.3, from 2023 and 2022, and the prebuilt archive and a build from source use
the same pins. A messenger opens files a peer sent, and a voice message
is loaded as soon as it is downloaded.

## Decision

On Android, media plays through androidx media3 (ExoPlayer), which Flutter's
`video_player` plugin reaches. media3 reads containers in managed code and decodes
with the platform's codecs.

- `SystemPlayer` implements media_kit's `PlatformPlayer` over a
  `VideoPlayerController`. The voice card, the composer and the viewer use
  media_kit's `Player` on every platform, and `createMediaPlayer` picks what is
  behind it.
- The viewer's video on Android is video_player's picture over the viewer's own
  controls (play or pause, seek, time), the ones its audio already had. Desktop
  keeps media_kit's picture with its Material controls.
- The frame for a video's previews comes from `MediaMetadataRetriever`
  (`MoshVideoFrame`). It reads a file, so the video is written to the app's cache
  for the call and removed after it.
- The app depends on one `media_kit_libs_*` package per desktop platform and iOS,
  not on the umbrella package that brought Android's.
- A network security configuration permits cleartext to `127.0.0.1` only. A
  streaming attachment comes from the app's loopback `MediaStreamServer`; media3
  follows the platform's cleartext policy, which libmpv ignored.

## Alternatives considered

- **Build libmpv from source in the F-Droid recipe.** It works: Aves is in
  F-Droid's main catalog with the same media_kit and builds libmpv from
  media-kit's scripts in its recipe. The app's code would not change and every
  format libmpv plays would keep playing. Rejected because the old ffmpeg stays
  unless we take over those scripts, the APK keeps its size, and the work pays
  off only if F-Droid accepts Mosh.
- **Our own ExoPlayer plugin.** It would repeat what video_player maintains.
- **The system's player on iOS too.** video_player has an AVFoundation backend,
  so `SystemPlayer` would serve it. Left for the iOS port: it cannot be checked
  before that exists.

| | media3 through video_player | libmpv from source in the recipe |
| --- | --- | --- |
| Code | 313 lines more in `lib/` and Kotlin, 345 lines of tests | none in the app; about 20 recipe lines and a build script |
| arm64 release APK | 94.6 MB to 82.6 MB: libmpv and its helper (12.8 MB) leave, media3 adds 1.1 MB of DEX | 94.6 MB |
| Build time | no new step | ffmpeg, mpv and seven more libraries on every F-Droid build; not measured |

## Consequences

- The Android build downloads no prebuilt libmpv. media3 comes from Google's
  Maven repository, like the other androidx libraries.
- Android plays what the device's codecs play: MP4, WebM and Matroska with
  H.264, HEVC, VP8, VP9 or AV1, and AAC, Opus, MP3 or FLAC sound. A format
  without a system codec (AVI, WMV) shows the file's card instead of playing.
- There are two players to keep working. On Android the video controls are
  plainer, and a playing voice message takes audio focus: it pauses other apps'
  sound and another message that was playing.
- A video pauses while the app is in the background; sound plays on, as before.
