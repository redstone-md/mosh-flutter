# Our libwebrtc builds

The libwebrtc call engine (`mosh-media/webrtc`) links Google's libwebrtc as
built from LiveKit's [webrtc-sdk fork](https://github.com/webrtc-sdk/webrtc)
at the commit in [build.json](build.json), by LiveKit's own build scripts as
patched in [webrtc-sys-patches](../webrtc-sys-patches/README.md): H.264 is
left out, and with it FFmpeg. libwebrtc itself is not patched. Those scripts
copy every header of the WebRTC tree, about 600 MB; the archive keeps only
the ones webrtc-sys's sources include, directly or not, on any platform
([libwebrtc-headers.mjs](../../scripts/support/libwebrtc-headers.mjs)), which
brings the Android archive from 108 MB to about 22 MB. Maven Central's free
tier publishes 80 MB a month.

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
`archives`. A version on Maven Central can never be removed, so a branch push
does not publish: after the commit that pins a new release's SHA-256, run the
workflow by hand on that branch (`gh workflow run libwebrtc.yml --ref
<branch>`), wait for the archive on repo1.maven.org, then rerun the pull
request's Android checks. Until then they fail to resolve it, and so would
main after a merge.

To change the build, edit the pin or the patches and give `release` a new
name: a published release is never replaced. To build locally, run
`node scripts/libwebrtc-build.mjs --target <rust triple>` (a 16 GB checkout)
and point `LK_CUSTOM_WEBRTC` at the resulting `<os>-<arch>-release`
directory in the work directory.
