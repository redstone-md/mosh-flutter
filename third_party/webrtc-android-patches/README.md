# Android native WebRTC

Signal WebRTC 7871n is the engine already pinned by RingRTC 2.72.1. Its official
Android binary returns null from `Rust_createPeerConnectionFactory`; accepting
desktop offers against that binary cannot produce a compatible call.

`source.json` pins the exact WebRTC and depot_tools commits. `mosh.patch` enables
the existing native owned-thread/injectable-network factory only for this Android
target, adds its GN dependencies, and uses WebRTC's Android audio module. The
software audio/video codecs and selected-pair SRTP protocol remain shared with
desktop. Android AudioManager owns physical routing; Cubeb remains desktop-only.

`node scripts/android-webrtc-build.mjs` reconstructs the pinned dependency graph,
verifies any existing local patch, builds the shared library and matching Java
API, then records input and product hashes outside the source checkout. Production
builds need no test media downloads or remote execution service. The GN arguments
are tracked here. Android's library has 16 KiB LOAD alignment.

`ANDROID_NDK_HOME=... node scripts/android-native-media-build.mjs` builds the
isolated Rust engine and stages the two shared libraries for Gradle. The app uses
the Java API from that same WebRTC build. Source trees/binaries are ignored;
patches, pins, notices and build scripts are committed. Existing WebRTC/RingRTC
license obligations in `mosh-media/THIRD_PARTY_NOTICES.md` apply to Android too.
