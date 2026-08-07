// Attachment card rendered inside a DM message bubble, ported from the
// React `AttachmentCard` (src/features/private-dm/AttachmentCard.tsx).
//
// FILE branch (in scope): file name, formatted size, transfer-state label,
// viewable MIME thumb button or non-viewable file/error icon, and progress
// bar while downloading.
//
// IMAGE preview branch (in scope): when the descriptor carries a non-empty
// `thumbnailB64` AND the mime is image/* or video/*, render the decoded
// thumbnail as a tappable `Image.memory` preview above the SAME bar the
// file card uses (name + meta + progress + actions). Mirrors React's
// `hasPreview = Boolean(thumbnail_b64) && (isImage || isVideo)` and the
// `attachment-card-media` JSX.
//
// Media viewing and external opening are dispatched by the owning screen;
// this card only emits the shared onOpen callback.
// Voice messages ARE in scope: descriptor.voice -> VoiceMessageCard
// (voice_message_card.dart, a separate file to keep this one focused).
// React flow: if (voice) return VoiceMessage; then if (hasPreview)
// return media-card; then return the file card with a viewable thumb button
// or a non-viewable file/error icon.
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

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/util/format.dart';

import 'package:mosh/src/features/dm/attachment_actions.dart';
import 'package:mosh/src/features/dm/attachment_thumb.dart';
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
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;
  final bool busy;

  /// React `onDownload`: fires `Gateway.downloadAttachment`; the screen
  /// invalidates the session provider so the downloading state re-renders.
  final void Function(String attachmentId) onDownload;

  /// React `onCancel`: fires `Gateway.cancelAttachment` (same pattern).
  final void Function(String attachmentId) onCancel;

  /// React `onOpen`: carries the descriptor to the owning screen, which
  /// routes media to MediaViewer or non-media files to the OS launcher.
  final void Function(AttachmentDescriptor descriptor) onOpen;

  @override
  Widget build(BuildContext context) {
    // React: if (descriptor.voice) return VoiceMessage; (ported).
    if (descriptor.voice != null) {
      final l = AppLocalizations.of(context)!;
      return VoiceMessageCard(
        descriptor: descriptor,
        view: view,
        busy: busy,
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
        busy: busy,
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
    final bar = _buildBar(
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
          AttachmentThumb(
            descriptor: descriptor,
            viewable: _isViewable,
            failed: failed,
            onOpen: onOpen,
          ),
          const SizedBox(width: 10),
          Expanded(child: bar),
          // React `attachment-bar`: `attachment-info` (flex-1) + actions
          // row to the right of name+meta+progress.
          const SizedBox(width: 10),
          AttachmentActions(
            descriptor: descriptor,
            view: view,
            state: state,
            outgoing: outgoing,
            busy: busy,
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
  /// (audio, pdf, ...) takes the file-card branch. Audio remains viewable in
  /// that branch and receives the open thumb button there.
  bool get _hasPreview {
    final thumb = descriptor.thumbnailB64;
    if (thumb == null || thumb.isEmpty) return false;
    final mime = descriptor.mime;
    return mime.startsWith('image/') || mime.startsWith('video/');
  }

  bool get _isViewable {
    final mime = descriptor.mime;
    return mime.startsWith('image/') ||
        mime.startsWith('video/') ||
        mime.startsWith('audio/');
  }
}

/// React `.attachment-card { max-width: 360px }`.
const double kAttachmentCardMaxWidth = 360;

/// React `.attachment-card-media { width: 320px; max-width: 320px }`.
const double kAttachmentMediaWidth = 320;

/// React `.attachment-preview { max-height: 260px }` -- the thumbnail keeps
/// its intrinsic height under that cap.
const double kAttachmentPreviewMaxHeight = 260;

/// Floor for the same box. A Flutter `Image.memory` reports no height until
/// it decodes, and none at all when it fails, so an unfloored preview
/// collapses to a zero-height box that swallows the open tap. React never
/// hits this because a broken `<img>` still lays out at its alt box.
const double kAttachmentPreviewMinHeight = 120;

/// React `.attachment-card { margin-top: 6px; padding: 8px 10px; border: 1px
/// solid var(--line); border-radius: 10px; background: var(--bg-2);
/// max-width: 360px }`, with `.attachment-card-failed` recolouring the
/// BORDER (not the fill) to --danger.
///
/// The media variant is the same shell under
/// `.attachment-card-media { padding: 0; width: 320px; overflow: hidden }`
/// -- the preview bleeds to the card edge, so the padding moves onto the
/// bar and the corners clip.
class _FileCardShell extends StatelessWidget {
  const _FileCardShell({
    required this.failed,
    required this.theme,
    required this.child,
    this.media = false,
  });

  final bool failed;
  final ThemeData theme;
  final Widget child;
  final bool media;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: BoxConstraints(
        maxWidth: media ? kAttachmentMediaWidth : kAttachmentCardMaxWidth,
      ),
      width: media ? kAttachmentMediaWidth : null,
      clipBehavior: media ? Clip.antiAlias : Clip.none,
      padding: media
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MoshColors.bg2,
        borderRadius: radius,
        border: Border.all(
          color: failed ? MoshColors.danger : MoshColors.line,
        ),
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
        style: const TextStyle(fontSize: 12.5, color: MoshColors.fg1),
      ),
      // `.attachment-info { gap: 2px }`.
      const SizedBox(height: 2),
      Text(
        meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: MoshColors.fg3),
      ),
      // `.attachment-progress { margin-top: 4px; height: 4px; border-radius:
      // 2px; background: var(--bg-3) }` with a --moss fill.
      if (state == AttachmentState.downloading) ...[
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 4,
            backgroundColor: MoshColors.bg3,
            color: MoshColors.moss,
            semanticsLabel: l.attachmentStateDownloading(percent),
          ),
        ),
      ],
    ],
  );
}

/// Renders the in-scope image/video media preview: the decoded base64 thumbnail
/// as a tappable `Image.memory` (rounded, height-constrained) above the
/// shared name+meta+progress bar + actions row. Mirrors React's
/// `attachment-card-media` shell with the `<img src=data:image/jpeg;base64,
/// thumbnail_b64>` payload.
///
/// IN SCOPE (ported 1:1 from React): the onOpen tap (`<button
/// onClick={onOpen}>` -> `GestureDetector` opens the local file) and the
/// actions row ([AttachmentActions] to the right of the bar, React's
/// `attachment-bar` flex row). The video play-overlay is decorative
/// (`Semantics(excludeSemantics: true)`); the wrapper uses the localized open
/// attachment action as its semantics label.
class _MediaPreviewCard extends StatelessWidget {
  const _MediaPreviewCard({
    required this.descriptor,
    required this.view,
    required this.own,
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;
  final bool busy;
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
    final previewLabel = l.attachmentOpenAria(descriptor.fileName);

    return _FileCardShell(
      failed: failed,
      theme: theme,
      media: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // React wraps the thumbnail in `<button onClick={onOpen}>`; the
          // preview is tappable via `GestureDetector` (opens the local file)
          // with the localized open-attachment action. The video
          // play-overlay is decorative and stays on top.
          Semantics(
            label: previewLabel,
            image: true,
            button: true,
            child: GestureDetector(
              onTap: () => onOpen(descriptor),
              // `.attachment-preview { width: 100%; background: var(--bg-0);
              // max-height: 260px }` -- the shell already clips the corners.
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: kAttachmentPreviewMinHeight,
                  maxHeight: kAttachmentPreviewMaxHeight,
                ),
                color: MoshColors.bg0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.memory(
                      bytes,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, _, __) => const SizedBox(
                        height: kAttachmentPreviewMinHeight,
                        width: double.infinity,
                        child: ColoredBox(
                          color: MoshColors.bg3,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 32,
                            color: MoshColors.fg3,
                          ),
                        ),
                      ),
                    ),
                    if (isVideo)
                      // `.attachment-play { width: 48px; height: 48px;
                      // border-radius: 999px; background: rgba(11,12,13,0.62);
                      // color: #fff }` -- decorative, so no semantics.
                      Semantics(
                        excludeSemantics: true,
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MoshColors.bg0.withValues(alpha: 0.62),
                          ),
                          child: const Icon(Icons.play_arrow,
                              size: 24, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // React `attachment-bar` (flex row): `attachment-info` (flex-1)
          // + `attachment-actions`. The bar takes the expanding slot; the
          // actions row sits to its right.
          Padding(
            // `.attachment-bar { padding: 8px 10px; gap: 10px }` -- the
            // media shell itself has no padding, so the bar carries it.
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildBar(
                    l: l,
                    fileName: descriptor.fileName,
                    totalSize: descriptor.totalSize,
                    state: state,
                    percent: percent,
                  ),
                ),
                const SizedBox(width: 10),
                AttachmentActions(
                  descriptor: descriptor,
                  view: view,
                  state: state,
                  outgoing: outgoing,
                  busy: busy,
                  onDownload: onDownload,
                  onCancel: onCancel,
                  onOpen: onOpen,
                  l: l,
                ),
              ],
            ),
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
