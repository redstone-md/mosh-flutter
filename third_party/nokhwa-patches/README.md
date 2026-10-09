# Pinned nokhwa camera source

`node scripts/native-camera-prepare.mjs` reconstructs nokhwa 0.10.11 from the
official crates.io archive, verifies its SHA-256, applies the complete patch and
verifies the resulting source-tree digest. Prepared source is ignored by Git;
review `source.json` and `mosh.patch`, not a locally installed package.

The macOS backend patch fixes its inverted input-format comparison, carries the
actual callback buffer resolution/format/timestamp, bounds its queue to the
latest frame and clears/quiesces callbacks during teardown. Initialization
failures clear an installed delegate before releasing its callback owner.
Blocking driver cancellation remains outside the library: the managed helper
can be killed and reaped even when a backend read does not return.

The companion [macOS binding patch](../nokhwa-macos-patches/README.md) controls
pixel layout and delegate lifetime. Both patches retain upstream Apache-2.0.
