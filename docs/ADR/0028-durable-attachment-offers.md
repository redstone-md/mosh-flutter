# ADR 0028: keep attachment offers in encrypted history

Date: 2026-09-25
Status: Accepted

## Context

History kept an attachment's display descriptor but discarded its chunk-crypto
manifest. After a restart, an uncached receiver had no transfer slot to
download from, and the sender had lost the key needed to serve its saved file.
Replaying the original MLS offer is not available after the session advances.

## Decision

Store the manifest as an optional field in the existing encrypted message
history row. On replay, match it to the descriptor before restoring an offer.
For a sent file, keep the manifest and load the stored bytes only when a peer
requests a chunk; verify the bytes against the manifest before serving with
the original key. The DM send path writes its new history row before returning.
No new table or bridge API is needed.

## Consequences

- New offers remain downloadable after either peer restarts, while the sender
  still has its saved file.
- Old rows without a manifest remain readable. Their cached files still open,
  but an uncached old offer cannot be recovered from that row.
- The manifest contains a chunk key, so it stays inside the already encrypted
  history row. It is never added to the display descriptor or Dart state.
