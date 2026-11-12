# Our libwebrtc builds

The libwebrtc call engine (`mosh-media/webrtc`) links Google's libwebrtc as
built from LiveKit's [webrtc-sdk fork](https://github.com/webrtc-sdk/webrtc)
at the commit in [build.json](build.json), by LiveKit's own build scripts as
patched in [webrtc-sys-patches](../webrtc-sys-patches/README.md): H.264 is
left out, and with it FFmpeg. libwebrtc itself is not patched.

[libwebrtc.yml](../../.github/workflows/libwebrtc.yml) builds Linux x64,
Windows x64, macOS arm64 and x64 and Android arm64 when the release named in
`build.json` does not exist yet, and publishes the archives as that GitHub
release (a pre-release that never becomes the latest, so the in-app update
check ignores it). Copy the SHA-256 of each archive from its `SHA256SUMS`
into `archives`. `node scripts/native-media-build.mjs --engine webrtc`
downloads and verifies the archive for its target.

The Android archive also goes to Maven Central as
`run.mosh:libwebrtc:<release without "libwebrtc-">:android-arm64-release@tar.gz`
(`maven` in `build.json` names the group and artifact), because F-Droid
accepts a prebuilt library only from a repository like that. The workflow's
`maven` job uploads it with [libwebrtc-maven.mjs](../../scripts/libwebrtc-maven.mjs),
signed with the key in the `MAVEN_GPG_PRIVATE_KEY` secret, through the Central
Portal user token in `MAVEN_CENTRAL_USERNAME` and `MAVEN_CENTRAL_PASSWORD`.
Gradle fetches it like any dependency and the Android build checks it against
`archives`, so publish a new release to Maven Central before an Android
build can use it.

To change the build, edit the pin or the patches and give `release` a new
name: a published release is never replaced. To build locally, run
`node scripts/libwebrtc-build.mjs --target <rust triple>` (a 16 GB checkout)
and point `LK_CUSTOM_WEBRTC` at the resulting `<os>-<arch>-release`
directory in the work directory.
