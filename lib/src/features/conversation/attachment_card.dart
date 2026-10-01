// Attachment card rendered inside a DM message bubble.
//
// FILE branch (in scope): file name, formatted size, transfer-state label,
// viewable MIME thumb button or non-viewable file/error icon, and progress
// bar while downloading.
//
// IMAGE preview branch: use the local image when available, otherwise the
// descriptor's image/video thumbnail. The preview opens above the same bar
// the file card uses (name + meta + progress + actions).
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
// Transfer controls live in [AttachmentActions]. Available files open by
// tapping the row; media opens from its preview via `onOpen(descriptor)`.
//
// State derivation: `outgoing = view?.direction == "outgoing"`,
// `state = view?.state ?? (outgoing ? "available" : "offered")`,
// `percent = progressPercent(view)`, and the meta line shows
// `formatBytes(total_size)` + (" \u00b7 " + stateLabel)` only when state !=
// "available".

import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;

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
/// are required. The file row opens only with a usable local path.
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
    this.messageFooter,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;
  final bool busy;
  final Widget? messageFooter;

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
        messageFooter: messageFooter,
      );
    }
    // Images can also preview their downloaded file when no thumbnail arrived.
    if (_hasPreview) {
      return _MediaPreviewCard(
        descriptor: descriptor,
        view: view,
        own: own,
        busy: busy,
        onDownload: onDownload,
        onCancel: onCancel,
        onOpen: onOpen,
        messageFooter: messageFooter,
      );
    }

    // File branch.
    final l = AppLocalizations.of(context)!;
    final outgoing = view?.direction == 'outgoing' || (view == null && own);
    final state = view?.state ??
        (outgoing ? AttachmentState.available : AttachmentState.offered);
    final percent = _progressPercent(view);
    final failed = state == AttachmentState.failed;
    final canOpen = state == AttachmentState.available &&
        (view?.localPath?.isNotEmpty ?? false);
    final bar = _buildBar(
      l: l,
      fileName: descriptor.fileName,
      totalSize: descriptor.totalSize,
      state: state,
      percent: percent,
      messageFooter: messageFooter,
    );
    return _FileCardShell(
      failed: failed,
      child: AttachmentOpenTarget(
        label: l.attachmentOpenAria(descriptor.fileName),
        onOpen: canOpen ? () => onOpen(descriptor) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AttachmentThumb(
              descriptor: descriptor,
              viewable: _isViewable,
              failed: failed,
              onOpen: canOpen ? null : onOpen,
            ),
            const SizedBox(width: 10),
            Expanded(child: bar),
            if (!outgoing && state != AttachmentState.available) ...[
              const SizedBox(width: 10),
              AttachmentActions(
                descriptor: descriptor,
                state: state,
                outgoing: outgoing,
                busy: busy,
                onDownload: onDownload,
                onCancel: onCancel,
                l: l,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Local images and image/video-with-thumbnail take the media branch; everything else
  /// (audio, pdf, ...) takes the file-card branch. Audio remains viewable in
  /// that branch and receives the open thumb button there.
  bool get _hasPreview {
    if (_localImagePreview(descriptor, view) != null) return true;
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

String? _localImagePreview(
    AttachmentDescriptor descriptor, AttachmentView? view) {
  final path = view?.localPath;
  return descriptor.mime.startsWith('image/') &&
          view?.state == AttachmentState.available &&
          path != null &&
          path.isNotEmpty
      ? path
      : null;
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

/// Embedded content shares the message surface. Files are flat rows;
/// media has a clipped 4px surface. Failed transfers keep a visible edge.
class _FileCardShell extends StatelessWidget {
  const _FileCardShell({
    required this.failed,
    required this.child,
    this.media = false,
  });

  final bool failed;
  final Widget child;
  final bool media;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: media ? kAttachmentMediaWidth : kAttachmentCardMaxWidth,
      ),
      width: media ? kAttachmentMediaWidth : null,
      clipBehavior: media ? Clip.antiAlias : Clip.none,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: MoshShapes.embedded,
        border: failed ? Border.all(color: MoshColors.danger) : null,
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
  Widget? messageFooter,
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
      Row(children: [
        Expanded(
            child: Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 11,
              color: MoshColors.fg3,
              fontFeatures: kLiveNumberFontFeatures),
        )),
        if (messageFooter case final footer?) ...[
          const SizedBox(width: 8),
          footer,
        ],
      ]),
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
