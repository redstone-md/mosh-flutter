// Attachment card rendered inside a DM message bubble, ported from the
// React `AttachmentCard` (src/features/private-dm/AttachmentCard.tsx).
// This atomic ports the in-scope display surface of the FILE branch and
// the IMAGE branch of the media-preview branch.
//
// FILE branch (in scope): file name, formatted size, transfer-state
// label, file icon (normal vs alert-on-failed), progress bar while
// downloading.
//
// IMAGE preview branch (in scope): when the descriptor carries a
// non-empty `thumbnailB64` AND the mime is image/* or video/*, render
// the decoded thumbnail as a non-interactive `Image.memory` preview
// above the SAME bar the file card uses (name + meta + progress). This
// mirrors React's `hasPreview = Boolean(thumbnail_b64) && (isImage ||
// isVideo)` and the `attachment-card-media` JSX.
//
// OUT OF SCOPE (deferred to later atomics -- the Gateway seam does not
// yet have download/cancel/open transfer methods):
//   - voice messages (descriptor.voice -> VoiceMessage branch in React);
//   - the video play-overlay (IconPlayerPlayFilled) on the media
//     preview -- the video-with-thumbnail branch renders the image
//     WITHOUT the play icon this atomic;
//   - the onOpen tap handler on the preview (<button onClick={onOpen}>
//     in React) -- the preview is non-interactive here;
//   - the `actions` block (download/cancel/retry/open buttons);
//   - the media viewer / streaming playback.
// React's flow is: `if (voice) return VoiceMessage;` (deferred), then
// `if (hasPreview) return media-card;` (this atomic, image-only surface),
// then `return file-card;` (the existing branch). Each deferred piece is
// noted inline where it would slot in.
//
// State derivation mirrors React exactly: `outgoing = view?.direction ===
// "outgoing"`, `state = view?.state ?? (outgoing ? "available" : "offered")`,
// `percent = progressPercent(view)`, and the meta line shows
// `formatBytes(total_size)` + (" \u00b7 " + stateLabel)` only when state !=
// "available" -- matching the React `state !== "available" ? ...` guard.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/util/format.dart';

/// Renders the in-scope file or image-preview attachment card for a DM
/// message bubble. See the file doc comment for what is in scope and
/// what is deferred.
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
    // React: `if (descriptor.voice) return VoiceMessage;`. The voice
    // message branch is DEFERRED (no VoiceMessage widget yet); the
    // file/media branches below render for now. When the voice branch
    // lands it slots in here as an early return.

    // React: `if (hasPreview) return <attachment-card-media>`. The
    // media-preview branch (image + video-with-thumbnail) is in scope
    // for the image surface this atomic.
    if (_hasPreview) {
      return _MediaPreviewCard(
        descriptor: descriptor,
        view: view,
        own: own,
      );
    }

    // React: `return <attachment-card>` (the file branch).
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
    final bar = _buildBar(
      theme: theme,
      l: l,
      fileName: descriptor.fileName,
      totalSize: descriptor.totalSize,
      state: state,
      percent: percent,
    );
    return _FileCardShell(
      failed: failed,
      theme: theme,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: bar),
        ],
      ),
    );
  }

  /// React: `hasPreview = Boolean(thumbnail_b64) && (isImage || isVideo)`.
  /// Image-with-thumbnail and video-with-thumbnail both take the media
  /// branch; everything else (audio, pdf, etc.) falls back to the file
  /// card. The video play-overlay is deferred (see _MediaPreviewCard).
  bool get _hasPreview {
    final thumb = descriptor.thumbnailB64;
    if (thumb == null || thumb.isEmpty) return false;
    final mime = descriptor.mime;
    return mime.startsWith('image/') || mime.startsWith('video/');
  }
}

/// Card chrome shared by the file and media branches: the rounded,
/// tinted container matching React's `attachment-card` shell. The
/// failed state tints the surface with `errorContainer`.
class _FileCardShell extends StatelessWidget {
  const _FileCardShell({
    required this.failed,
    required this.theme,
    required this.child,
  });

  final bool failed;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Kept compact so it fits inside the bubble width (maxWidth 360 in
      // `_DmMessageRow`). Mirrors React's `attachment-card` styling.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: failed
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Shared name + meta + progress bar (DRY) used by both the file card and
/// the media preview card. Mirrors React's `meta` line + `progressBar`:
/// `formatBytes(total_size)` plus (" \u00b7 " + stateLabel) when state !=
/// "available", and a `LinearProgressIndicator` while downloading.
/// Returns a tight `Column` (no leading icon) so the file card wraps it
/// in an icon `Row` and the media card stacks it under the preview.
Widget _buildBar({
  required ThemeData theme,
  required AppLocalizations l,
  required String fileName,
  required BigInt totalSize,
  required AttachmentState state,
  required int percent,
}) {
  final size = formatBytes(totalSize);
  final stateLabel = _attachmentStateLabel(l, state, percent);
  // React omits the state label entirely when state == "available"
  // (only the size renders); every other state appends " \u00b7 {label}".
  final meta =
      state == AttachmentState.available ? size : '$size \u00b7 $stateLabel';
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      Text(
        meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
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
  );
}

/// Renders the in-scope IMAGE media preview: the decoded base64 thumbnail
/// as a non-interactive `Image.memory` (rounded, height-constrained)
/// above the shared name+meta+progress bar. Mirrors React's
/// `attachment-card-media` shell with the `<img src=data:image/jpeg;base64,
/// thumbnail_b64>` payload.
///
/// DEFERRED (later atomics, noted for 1:1 review):
///   - the video play-overlay (`IconPlayerPlayFilled` in React): the
///     video-with-thumbnail branch renders the image WITHOUT the play
///     icon this atomic;
///   - the onOpen tap (`<button onClick={onOpen}>`): the preview is
///     non-interactive (no Gateway `open` method yet);
///   - the actions row (download/cancel/retry/open buttons).
class _MediaPreviewCard extends StatelessWidget {
  const _MediaPreviewCard({
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
    final thumb = descriptor.thumbnailB64!;
    final bytes = Uint8List.fromList(base64Decode(thumb));

    return _FileCardShell(
      failed: failed,
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Non-interactive preview (no onOpen tap this atomic). React
          // wraps the img in `<button onClick={onOpen}>`; that tap and the
          // video play-overlay are deferred. Constrained so the preview
          // does not blow up the bubble.
          Semantics(
            label: 'Image preview: ${descriptor.fileName}',
            image: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, _, __) => SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 32,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _buildBar(
            theme: theme,
            l: l,
            fileName: descriptor.fileName,
            totalSize: descriptor.totalSize,
            state: state,
            percent: percent,
          ),
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
