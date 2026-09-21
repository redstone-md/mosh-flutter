// Attachment card rendered inside a DM message bubble.
//
// FILE branch (in scope): file name, formatted size, transfer-state label,
// viewable MIME thumb button or non-viewable file/error icon, and progress
// bar while downloading.
//
// IMAGE preview branch (in scope): when the descriptor carries a non-empty
// `thumbnailB64` AND the mime is image/* or video/*, render the decoded
// thumbnail as a tappable `Image.memory` preview above the SAME bar the
// file card uses (name + meta + progress + actions).
//
// Media viewing and external opening are dispatched by the owning screen;
// this card only emits the shared onOpen callback.
// Voice messages ARE in scope: descriptor.voice -> VoiceMessageCard
// (voice_message_card.dart, a separate file to keep this one focused).
// Branch order: if (voice) return VoiceMessage; then if (hasPreview)
// return media-card; then return the file card with a viewable thumb button
// or a non-viewable file/error icon.
//
// VIDEO play-overlay is IN SCOPE: a centered play glyph overlays the
// thumbnail when the mime is a video; decorative
// (`Semantics(excludeSemantics: true)`), the wrapper's image semantics
// carries the label.
//
// ACTIONS ROW + onOpen tap (IN SCOPE): the 4-state machine lives in
// [AttachmentActions] (attachment_actions.dart). The preview tap opens the
// local file via `onOpen(descriptor)`.
//
// State derivation: `outgoing = view?.direction == "outgoing"`,
// `state = view?.state ?? (outgoing ? "available" : "offered")`,
// `percent = progressPercent(view)`, and the meta line shows
// `formatBytes(total_size)` + (" \u00b7 " + stateLabel)` only when state !=
// "available".

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/util/format.dart';

import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/features/conversation/attachment_thumb.dart';
import 'package:mosh/src/features/conversation/voice_message_card.dart';

part 'attachment_card_branches.dart';

/// Renders the in-scope file or image-preview attachment card for a DM
/// message bubble (see the file doc for scope). `own` is the row's own-
/// message flag; when a view is present `outgoing` is derived from
/// `view.direction == "outgoing"`, otherwise we fall back to `own` so an own
/// message with no transfer state renders as `available`.
///
/// Transfer-action callbacks (onDownload / onCancel / onOpen): all three
/// are REQUIRED -- the DM screen always wires them. The Open button is
/// disabled by [AttachmentActions] when `view.localPath == null`.
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

  /// Fires `Gateway.downloadAttachment`; the screen invalidates the session
  /// provider so the downloading state re-renders.
  final void Function(String attachmentId) onDownload;

  /// Fires `Gateway.cancelAttachment`.
  final void Function(String attachmentId) onCancel;

  /// Carries the descriptor to the owning screen, which routes media to
  /// MediaViewer or non-media files to the OS launcher.
  final void Function(AttachmentDescriptor descriptor) onOpen;

  @override
  Widget build(BuildContext context) {
    // Voice messages render as their own card.
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
    // Image/video-with-thumbnail takes the media branch.
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

    // File branch.
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
          // Info (expanding) + actions row to the right.
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

  /// `hasPreview = thumbnail non-empty && (image/* || video/*)`.
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

/// Max width of the file card.
const double kAttachmentCardMaxWidth = 360;

/// Fixed width of the media-preview card.
const double kAttachmentMediaWidth = 320;

/// Cap on the preview height -- the thumbnail keeps its intrinsic height
/// under that cap.
const double kAttachmentPreviewMaxHeight = 260;

/// Floor for the same box. A Flutter `Image.memory` reports no height until
/// it decodes, and none at all when it fails, so an unfloored preview
/// collapses to a zero-height box that swallows the open tap.
const double kAttachmentPreviewMinHeight = 120;

/// Card shell: 6px top margin, 8px/10px padding, hairline border, 10px
/// radius, bg-2 fill, 360px max width. A failed transfer recolours the
/// BORDER (not the fill) to danger.
///
/// The media variant drops the padding and clips the corners: the preview
/// bleeds to the card edge, so the padding moves onto the bar.
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

/// Shared name + meta + progress bar (DRY) used by both branches:
/// `formatBytes(total_size)` plus (" \u00b7 " + stateLabel) when state !=
/// "available", and a `LinearProgressIndicator` while downloading. A tight
/// `Column` (no icon) so the file card wraps it in an icon `Row` and the
/// media card stacks it.
Widget _buildBar({
  required AppLocalizations l,
  required String fileName,
  required BigInt totalSize,
  required AttachmentState state,
  required int percent,
}) {
  final size = formatBytes(totalSize);
  final stateLabel = _attachmentStateLabel(l, state, percent);
  // The state label is omitted when state == "available" (size only);
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
      // 2px between name and meta.
      const SizedBox(height: 2),
      Text(
        meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: MoshColors.fg3),
      ),
      // 4px tall moss progress bar on bg-3, shown while downloading.
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

/// 0 when no view or `chunkCount == 0`, else
/// `min(100, completed / total * 100)`. BigInt math then `.toInt()`
/// (percent fits 0..100 so the narrowing is safe).
int _progressPercent(AttachmentView? view) {
  if (view == null || view.chunkCount == BigInt.zero) return 0;
  final raw = (view.completedChunks * BigInt.from(100)) ~/ view.chunkCount;
  final clamped = raw > BigInt.from(100) ? BigInt.from(100) : raw;
  return clamped.toInt();
}

/// Localized transfer-state label; the downloading label interpolates the
/// percent.
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
