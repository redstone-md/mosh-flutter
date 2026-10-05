# Issue 56: two levels of attachment previews

The user approved this design on 2026-10-05: every supported image keeps a small
inline thumbnail; a clear preview loads automatically through the existing blob
transfer. Sending an image without its thumbnail is not an acceptable fallback.

## Scope

- DM, private groups including organization groups, and public channels.
- Shared picker, drag/drop and clipboard ingestion produce both previews using
  the existing Dart image encoder. Decode once, preserve the original bytes.
- Inline JPEG stays within a small fixed budget. The normal preview retains the
  existing 320-pixel maximum edge and travels as an auxiliary encrypted blob.
- Main attachment manifests and their author proofs retain their existing
  canonical representation. A shared offer carries the additional preview
  descriptor beside the main manifest, inside the existing authenticated frame.
  Old readers ignore the additional offer field and still show the miniature.
- The existing transfer owner handles both blobs. Auxiliary previews have no
  message row or visible download action. They load automatically with bounded
  priority, retry after interruption, and restore from encrypted history.
- Each preview descriptor binds to its parent attachment and authenticated author.
  Validate size, MIME, identity and relationship before automatic downloading.
- Use the existing chunk encryption with an independent key and nonce prefix for
  each preview. Public channels retain their existing public confidentiality model.
- Persist the auxiliary manifest with the parent message, retain both cache leases,
  and erase both blobs only when no other history or active transfer references them.
- Flutter observes a local preview path separately from original-file availability.
  It keeps showing the miniature while the preview is loading or retrying.
- Extend the bridge payload with optional full-preview bytes and the transfer view
  with an optional preview path, then regenerate and check the committed bindings.
- Report an oversized final frame as an input/transfer failure, not lost network
  connectivity. Do not increase Moss limits or change its sources.
- No new dependencies, persistence tables, manual network settings or download UI.

## Implementation order

1. Lock down the reproduced detailed-PNG ingest and native publish failure.
2. Generate a bounded miniature plus normal preview in the shared Dart ingest.
3. Add the shared auxiliary-preview offer and transfer ownership. Prove automatic
   chunk download, request priority and parent-only snapshots through `Transfer`.
4. Connect DM/group/channel send and receive paths and bridge payloads.
5. Restore both offers, resume preview downloads, and extend reference-aware erasure.
6. Render the normal preview as soon as its verified local file becomes available.
7. Add protocol compatibility, authorization and real native peer checks.
8. Update architecture/ADR, run required checks, review both standards and spec,
   commit and open a real PR against current main.

## Checks and observed interfaces

Tests exercise the existing application interfaces requested by root AGENTS.md:

- `ingestAttachment`: original bytes round-trip, decodable bounded miniature,
  clear 320-pixel preview for a detailed PNG, and all three input routes.
- Runtime `send_attachment` and `poll`: real MLS/Moss publication, one message
  per file, accepted packet size, verified author and old-reader compatibility.
- `Transfer`: automatic auxiliary download without starting the original,
  bounded priority, verified completion, corrupted chunks, retry and replay.
- Existing encrypted history/deletion operations: restart retains both offers,
  pending downloads resume, deleted messages cannot request or retain previews,
  and another message's shared cache remains available.
- `AttachmentCard` with `test/support`: miniature before completion, normal
  preview afterwards, and unchanged original download/open controls.
- Flutter format/analyze/test, Rust fmt/clippy and real Moss test suite, bridge
  generation/drift, source-size limits and changed-code coverage.

## Risks to resolve before completion

- New fields must not change old manifest origin verification. Test independently
  against the legacy representation instead of relying on Serde round trips.
- Auxiliary offers must not allow automatic downloading of unbounded files or
  substitution of another attachment's preview.
- A full preview path must never imply the original image is downloaded.
- History and cache deletion must preserve the parent/preview relationship across
  restart and concurrent use by another message.
- Small previews remain available while the sender is offline; fetching the clear
  preview still requires an available verified source, as other blob transfers do.

Sources: [issue 56](https://github.com/redstone-md/mosh-flutter/issues/56),
[Telegram thumbnails](https://core.telegram.org/api/files#stripped-thumbnails),
ADR 0027, ADR 0028, ADR 0037 and ADR 0040.
