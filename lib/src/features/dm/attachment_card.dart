// Attachment card rendered inside a DM message bubble, ported from the
// React `AttachmentCard` (src/features/private-dm/AttachmentCard.tsx).
// This atomic ports ONLY the in-scope display surface of the FILE branch:
// the file name, the formatted size, the transfer-state label, the file
// icon (normal vs alert-on-failed), and a progress bar while downloading.
//
// OUT OF SCOPE (deferred to later atomics -- the Gateway seam does not yet
// have download/cancel/open transfer methods):
//   - voice messages (descriptor.voice -> VoiceMessage branch in React);
//   - image/video thumbnail preview (descriptor.thumbnail_b64 -> the
//     `attachment-card-media` branch in React);
//   - the `actions` block (download/cancel/retry/open buttons);
//   - the media viewer / streaming playback.
// Each deferred piece is noted inline where it would slot in.
//
// State derivation mirrors React exactly: `outgoing = view?.direction ===
// "outgoing"`, `state = view?.state ?? (outgoing ? "available" : "offered")`,
// `percent = progressPercent(view)`, and the meta line shows
// `formatBytes(total_size)` + (" \u00b7 " + stateLabel)` only when state !=
// "available" -- matching the React `state !== "available" ? ...` guard.

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/util/format.dart';

/// Renders the in-scope file attachment card for a DM message bubble.
/// See the file doc comment for what is deferred.
///
/// `own` is the row's own-message flag (from `fromDevice == ownDeviceName`).
/// When a view is present we mirror React and derive `outgoing` from
/// `view.direction == "outgoing"`; otherwise we fall back to `own` so an
/// own message with no transfer state renders as `available` (not
/// `offered`), matching React's `view?.state ?? (outgoing ? "available"
/// : "offered")`.
class AttachmentCard extends StatelessWidget {
  const AttachmentCard({
    super.key,
    required this.descriptor,
    required this.view,
    required this.own,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final outgoing = view?.direction == 'outgoing' || (view == null && own);
    final state = view?.state ??
        (outgoing ? AttachmentState.available : AttachmentState.offered);
    final percent = _progressPercent(view);
    final failed = state == AttachmentState.failed;
    final icon =
        failed ? Icons.error_outline : Icons.insert_drive_file_outlined;
    final iconColor = failed ? theme.colorScheme.error : null;
    final size = formatBytes(descriptor.totalSize);
    final stateLabel = _attachmentStateLabel(l, state, percent);
    // React omits the state label entirely when state == "available"
    // (only the size renders); every other state appends " \u00b7 {label}".
    final meta = state == AttachmentState.available
        ? size
        : '$size \u00b7 $stateLabel';

    return Container(
      // Kept compact so it fits inside the bubble width (maxWidth 360 in
      // `_DmMessageRow`). Mirrors React's `attachment-card` styling: a
      // column of [row(icon, info(name + meta))] + optional progress.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: failed
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      descriptor.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state == AttachmentState.downloading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 4,
                semanticsLabel: l.attachmentStateDownloading(percent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `progressPercent(view)` ported 1:1 from React: 0 when there is no view or
/// `chunk_count == 0`, else `min(100, round(completed / total * 100))`.
/// BigInt math then `.toInt()` for the int return (percent fits 0..100 so
/// the narrowing is safe).
int _progressPercent(AttachmentView? view) {
  if (view == null || view.chunkCount == BigInt.zero) return 0;
  final raw = (view.completedChunks * BigInt.from(100)) ~/ view.chunkCount;
  final clamped = raw > BigInt.from(100) ? BigInt.from(100) : raw;
  return clamped.toInt();
}

/// `transferStateLabel(state, percent)` ported 1:1 from React, routed
/// through AppLocalizations so the labels are localized. The downloading
/// label interpolates the integer percent.
String _attachmentStateLabel(
    AppLocalizations l, AttachmentState state, int percent) {
  switch (state) {
    case AttachmentState.available:
      return l.attachmentStateAvailable;
    case AttachmentState.downloading:
      return l.attachmentStateDownloading(percent);
    case AttachmentState.failed:
      return l.attachmentStateFailed;
    case AttachmentState.cancelled:
      return l.attachmentStateCancelled;
    case AttachmentState.offered:
      return l.attachmentStateOffered;
  }
}