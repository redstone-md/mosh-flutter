# ADR 0041: bounded miniature and separately transferred preview

Date: 2026-10-06
Status: Accepted

## Context

Issue #56 reports failed screenshot attachment sends and a misleading network
error. A detailed 640×480 PNG reproduced the failure through the actual image
ingest and MLS/Moss publication. Its 30,280-byte inline JPEG base64 expands again
inside encrypted group control and sender proofs, exceeding Moss's 65,536-byte
application payload ceiling. The original file size is not the failing limit.

## Decision

Decode supported images once in a background isolate with the existing `image`
package. Keep their original bytes. Produce a JPEG miniature at quality 50 with
an edge of at most 48 pixels, reducing that edge until its base64 fits 2,048 bytes.
Also produce the existing 320-pixel JPEG preview at quality 70. Picker, drop and
clipboard (copied images and, see `docs/Features/clipboard-attachments.md`,
copied files) use the same ingest. An unreadable image reports a localized preview
error and is refused. Existing best-effort video capture remains supported.
Bake EXIF orientation before resizing and omit the remaining EXIF. Retain valid
RGB ICC profiles, with a 64 KiB extraction/inflation cap, in standard JPEG APP2
chunks. The pinned image encoder's ICC headers are incompatible with native
readers, so a small metadata helper handles that container while reusing its
pixel codec. Miniatures omit the profile only if it cannot fit their byte budget.
The clear JPEG must fit 128 KiB before ingest hands it to the bridge; unsupported
or oversized color profiles report the preview error. Original metadata stays intact.

The miniature stays inline. Transfer the clear JPEG as an auxiliary attachment
through the existing encrypted chunk engine. `AttachmentOffer` flattens the
unchanged parent manifest and carries optional `preview_manifest` beside it.
Do not add the child to the canonical `AttachmentManifest`: older readers ignore
the sibling extension and can still verify the unchanged parent author proof.

The preview uses its own chunk key and nonce, ID `<attachment-id>/preview`, JPEG
MIME, fixed filename and a maximum of 128 KiB. Its signed conversation context is
`<conversation>/preview/<attachment-id>` and its signer must equal the parent's.
DM and group offers remain MLS encrypted, and groups retain sender proofs and
organization envelopes. Channels retain their existing public model.

The shared `Transfer` owner hides auxiliary slots from snapshots. It starts at
most four preview downloads automatically. Voice requests precede previews,
which precede originals; all share the existing bounded chunk request budget.
Missing chunks keep the existing retry cadence. Failed verification or cache
writes restart a preview after five seconds without changing the parent's
download state. The miniature remains visible while the preview is unavailable.

Store the optional child manifest in the parent's existing encrypted history
row. Replay verifies the pair before restoring automatic requests. Verify cached
preview size and SHA-256 before reuse; senders reload original chunk keys after
restart. Parent erasure discards both transfer slots and queues both cache files
for the existing reference-aware collector. Other messages and unopened history
retain their preview references.

The bridge adds optional `preview_base64` to sends and `preview_path` to transfer
views. A local preview path never means the original is downloaded. Cards show
the cached original when available, otherwise the clear preview, otherwise the
miniature. A missing or undecodable clear file falls back to the miniature.
Cards bound cached images to 640×520 pixels using Flutter's aspect-preserving
resize policy. Automatic clear previews additionally reject intrinsic dimensions
above 320 pixels before codec instantiation. Inline miniatures have a 1,024-pixel
edge allowance for legacy portraits produced before the EXIF sizing fix. Both
limits bound the source bitmap before decode; a byte limit alone cannot do that.
Invalid clear previews keep the miniature visible.

Check final serialized control packets against Moss's application ceiling.
`PayloadTooLarge` crosses the existing typed error boundary and displays a size
error. It does not report lost connectivity. Refused publication releases both
prepared transfers' cache leases. Moss sources and limits are unchanged.

## Consequences and verification

Old clients show the miniature and can still download originals. Old history
without auxiliary descriptors remains readable. A clear preview that has not
been cached requires an available sender, as other attachment blobs do.
No new dependency or persistence table is needed. Cached originals also verify
size and SHA-256 on restart using a fixed-size read buffer. Repeated history rows
keep one preview installation and do not consume another download slot.

Tests cover detailed PNG ingest, paperclip and drop callbacks, miniature-to-file
rendering, protocol compatibility, signer/parent binding, limits, corrupt chunks,
request priority, bounded concurrency, encrypted replay and reference-aware
cleanup. Independent processes using real bridge owners, MLS and Moss exercise
DM, group and channel reception, receiver restart and parent deletion. Group
tests verify organization-wrapped packets at the maximum miniature budget and
sender restart serving with the saved keys.

Existing runtime send assembly, history replay and deletion admission retain
their established function-length exceptions. They keep protocol fields and
atomic history transitions together. The shared `Transfer` owner retains its
existing type-length exception; preview scheduling and replay live in separate
modules, and its main file is shorter than before this change. Generated bridge
files and the existing video capture routine retain their existing exceptions.
Complete protocol scenario tests may exceed 50 lines to keep setup, restart and
delivery assertions together. New production modules stay below 400 lines.

Pattern references: [Telegram stripped thumbnails](https://core.telegram.org/api/files#stripped-thumbnails)
and [Matrix encrypted thumbnail files](https://spec.matrix.org/unstable/client-server-api/).
ICC chunks follow the [ICC embedding convention](https://archive.color.org/files/technotes/ICC-Technote-ProfileEmbedding.pdf).
The 568-byte color-test fixture is a synthetic RGB ICC profile generated with
LCMS using D65, P3 primaries and gamma 2.2; tests need only the committed bytes.
