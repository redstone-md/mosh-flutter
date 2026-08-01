// Attachment card rendered inside a DM message bubble, ported from the
// React `AttachmentCard` (src/features/private-dm/AttachmentCard.tsx).
//
// FILE branch (in scope): file name, formatted size, transfer-state label,
// file icon (normal vs alert-on-failed), progress bar while downloading.
//
// IMAGE preview branch (in scope): when the descriptor carries a non-empty
// `thumbnailB64` AND the mime is image/* or video/*, render the decoded
// thumbnail as a tappable `Image.memory` preview above the SAME bar the
// file card uses (name + meta + progress + actions). Mirrors React's
// `hasPreview = Boolean(thumbnail_b64) && (isImage || isVideo)` and the
// `attachment-card-media` JSX.
//
// OUT OF SCOPE (deferred): the media viewer / streaming playback, and
// the cross-platform open launcher (this atomic ships Windows cmd /c
// start; non-Windows is a TODO no-op, a later atomic wires open_filex).
// Voice messages ARE in scope: descriptor.voice -> VoiceMessageCard
// (voice_message_card.dart, a separate file to keep this one focused).
// React flow: if (voice) return VoiceMessage; then if (hasPreview)
// return media-card; then return file-card.
//
// VIDEO play-overlay is IN SCOPE: a centered `Icons.play_circle_filled`
// overlays the thumbnail when the mime is a video (React's
// `<IconPlayerPlayFilled>`); decorative (`Semantics(excludeSemantics: true)`),
// the wrapper's image semantics carries the label.
//
// ACTIONS ROW + onOpen tap (IN SCOPE): ported 1:1 from React's `<div
// className="attachment-actions">` state machine (see [AttachmentActions]
// for the 4-state table -- now in attachment_actions.dart as AttachmentActions).
// The preview
// tap opens the local file via
// `onOpen(descriptor)`.
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

import 'package:mosh/src/features/dm/attachment_actions.dart';
import 'package:mosh/src/features/dm/voice_message_card.dart';

/// Renders the in-scope file or image-preview attachment card for a DM
/// message bubble (see the file doc for scope). `own` is the row's own-
/// message flag; when a view is present `outgoing` is derived from
/// `view.direction == "outgoing"`, otherwise we fall back to `own` so an own
/// message with no transfer state renders as `available` (React's
/// `view?.state ?? (outgoing ? "available" : "offered")`).
///
/// Transfer-action callbacks (React `onDownload` / `onCancel` / `onOpen`):
/// all three are REQUIRED -- the DM screen always wires them. The Open
/// button is disabled by [AttachmentActions] when `view.localPath == null`
/// (React's `disabled={!view?.local_path}`).
class AttachmentCard extends StatelessWidget {
  const AttachmentCard({
    super.key,
    required this.descriptor,
    required this.view,
    required this.own,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;

  /// React `onDownload`: fires `Gateway.downloadAttachment`; the screen
  /// invalidates the session provider so the downloading state re-renders.
  final void Function(String attachmentId) onDownload;

  /// React `onCancel`: fires `Gateway.cancelAttachment` (same pattern).
  final void Function(String attachmentId) onCancel;

  /// React `onOpen`: opens `view.localPath` via a dart:io launcher (Windows
  /// `cmd /c start`; non-Windows is a TODO no-op). Carries the descriptor
  /// so a later viewer refactor can route to it.
  final void Function(AttachmentDescriptor descriptor) onOpen;

  @override
  Widget build(BuildContext context) {
    // React: if (descriptor.voice) return VoiceMessage; (ported).
    if (descriptor.voice != null) {
      final l = AppLocalizations.of(context)!;
      return VoiceMessageCard(
        descriptor: descriptor,
        view: view,
        onDownload: onDownload,
        playLabel: l.voiceMessagePlayLabel,
        pauseLabel: l.voiceMessagePauseLabel,
      );
    }
    // React: if (hasPreview) return <attachment-card-media>.
    // React: `if (hasPreview) return <attachment-card-media>`.
    if (_hasPreview) {
      return _MediaPreviewCard(
        descriptor: descriptor,
        view: view,
        own: own,
        onDownload: onDownload,
        onCancel: onCancel,
        onOpen: onOpen,
      );
    }

    // React: `return <attachment-card>` (file branch).
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
          // React `attachment-bar`: `attachment-info` (flex-1) + actions
          // row to the right of name+meta+progress.
          const SizedBox(width: 4),
          AttachmentActions(
            descriptor: descriptor,
            view: view,
            state: state,
            outgoing: outgoing,
            busy: false,
            onDownload: onDownload,
            onCancel: onCancel,
            onOpen: onOpen,
            l: l,
          ),
        ],
      ),
    );
  }

  /// React: `hasPreview = Boolean(thumbnail_b64) && (isImage || isVideo)`.
  /// Image/video-with-thumbnail take the media branch; everything else
  /// (audio, pdf, ...) falls back to the file card.
  bool get _hasPreview {
    final thumb = descriptor.thumbnailB64;
    if (thumb == null || thumb.isEmpty) return false;
    final mime = descriptor.mime;
    return mime.startsWith('image/') || mime.startsWith('video/');
  }
}

/// Card chrome shared by both branches: the rounded, tinted container
/// matching React's `attachment-card` shell (failed tints `errorContainer`).
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: failed
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Shared name + meta + progress bar (DRY) used by both branches. Mirrors
/// React's `meta` + `progressBar`: `formatBytes(total_size)` plus
/// (" \u00b7 " + stateLabel) when state != "available", and a
/// `LinearProgressIndicator` while downloading. A tight `Column` (no icon)
/// so the file card wraps it in an icon `Row` and the media card stacks it.
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
  // React omits the state label when state == "available" (size only);
  // every other state appends " \u00b7 {label}".
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
/// as a tappable `Image.memory` (rounded, height-constrained) above the
/// shared name+meta+progress bar + actions row. Mirrors React's
/// `attachment-card-media` shell with the `<img src=data:image/jpeg;base64,
/// thumbnail_b64>` payload.
///
/// IN SCOPE (ported 1:1 from React): the onOpen tap (`<button
/// onClick={onOpen}>` -> `GestureDetector` opens the local file) and the
/// actions row ([AttachmentActions] to the right of the bar, React's
/// `attachment-bar` flex row). The video play-overlay is decorative
/// (`Semantics(excludeSemantics: true)`); the wrapper semantics label
/// reflects the content ("Image preview: ..." / "Video preview: ...").
class _MediaPreviewCard extends StatelessWidget {
  const _MediaPreviewCard({
    required this.descriptor,
    required this.view,
    required this.own,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;
  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;

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
    // React: `isVideo = descriptor.mime.startsWith("video/")`. Drives
    // the centered play-overlay on top of the thumbnail image.
    final isVideo = descriptor.mime.startsWith('video/');
    final previewLabel = isVideo
        ? 'Video preview: ${descriptor.fileName}'
        : 'Image preview: ${descriptor.fileName}';

    return _FileCardShell(
      failed: failed,
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // React wraps the thumbnail in `<button onClick={onOpen}>`; the
          // preview is tappable via `GestureDetector` (opens the local
          // file). The video play-overlay is decorative and stays on top.
          Semantics(
            label: previewLabel,
            image: true,
            button: true,
            child: GestureDetector(
              onTap: () => onOpen(descriptor),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
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
                      if (isVideo)
                        // Decorative play overlay (React's
                        // `attachment-play` span); excluded from semantics.
                        Positioned.fill(
                          child: Center(
                            child: Semantics(
                              excludeSemantics: true,
                              child: Icon(
                                Icons.play_circle_filled,
                                size: 40,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // React `attachment-bar` (flex row): `attachment-info` (flex-1)
          // + `attachment-actions`. The bar takes the expanding slot; the
          // actions row sits to its right.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _buildBar(
                  theme: theme,
                  l: l,
                  fileName: descriptor.fileName,
                  totalSize: descriptor.totalSize,
                  state: state,
                  percent: percent,
                ),
              ),
              const SizedBox(width: 4),
              AttachmentActions(
                descriptor: descriptor,
                view: view,
                state: state,
                outgoing: outgoing,
                busy: false,
                onDownload: onDownload,
                onCancel: onCancel,
                onOpen: onOpen,
                l: l,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `progressPercent(view)` ported 1:1 from React: 0 when no view or
/// `chunkCount == 0`, else `min(100, round(completed / total * 100))`. BigInt
/// math then `.toInt()` (percent fits 0..100 so the narrowing is safe).
int _progressPercent(AttachmentView? view) {
  if (view == null || view.chunkCount == BigInt.zero) return 0;
  final raw = (view.completedChunks * BigInt.from(100)) ~/ view.chunkCount;
  final clamped = raw > BigInt.from(100) ? BigInt.from(100) : raw;
  return clamped.toInt();
}

/// `transferStateLabel(state, percent)` ported 1:1 from React, routed
/// through AppLocalizations. The downloading label interpolates the percent.
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
