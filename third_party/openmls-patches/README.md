# OpenMLS source patch

Mosh uses OpenMLS 0.8.1 with historical lifetime validation and the reviewed
corrections recorded in [the review notes](../../docs/Proposals/openmls-review-corrections.md).
The complete delta is [mosh.patch](mosh.patch). Upstream source and tests are
reconstructed locally instead of maintained as an 80,000-line mirror.

```sh
node scripts/openmls-prepare.mjs
```

[source.json](source.json) pins the crates.io archive, its SHA-256, upstream
commit and the SHA-256 of the complete patched source tree. Preparation verifies
both hashes, applies the patch in a temporary directory and publishes only
verified source. The result at `third_party/openmls/` is the byte-identical tree
used before this migration, including its manifest, lockfile, license, upstream
tests and Mosh regression tests. Existing source edits cause preparation to fail.

CI setup, Moss preparation, the native test runner and Flutter's Cargokit entry
prepare automatically. Before using Cargo or bridge codegen directly on a fresh
checkout, run the command above. Node.js, Git and tar are required, as they are
for the existing native development tools.

The archive is cached in `.dart_tool/native-sources/`. Once prepared, subsequent
builds need no download. For disconnected builds, preserve this directory and
run `node scripts/openmls-prepare.mjs --offline` before `cargo --offline`.
A fresh checkout requires either the cached archive or access to crates.io.

To update the patch, edit the materialized source, produce a unified diff against
the pinned archive, then update `sourceSha256`. `sourceHash` in the preparation
script computes that hash. Run `node --test scripts/openmls-prepare.test.mjs`
and the core checks before committing. Patch updates retain all upstream files;
do not trim tests or license notices. Upstream files keep their documented size
exceptions. The MIT notice is retained in [LICENSE](LICENSE) and in the source.
