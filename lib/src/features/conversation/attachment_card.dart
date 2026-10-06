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
import 'package:mosh/src/features/conversation/conversation_attachment.dart';
import 'package:mosh/src/features/conversation/attachment_thumb.dart';
import 'attachment_preview_image.dart';
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
    final attachment =
        ConversationAttachment(descriptor: descriptor, view: view, own: own);
    // Voice messages render as their own card.
    if (descriptor.voice != null) {
      final l = AppLocalizations.of(context)!;
      return VoiceMessageCard(
        descriptor: descriptor,
        view: view,
        own: own,
        busy: busy,
        onDownload: onDownload,
        playLabel: l.voiceMessagePlayLabel,
        pauseLabel: l.voiceMessagePauseLabel,
        messageFooter: messageFooter,
      );
    }
    // Images can also preview their downloaded file when no thumbnail arrived.
    if (attachment.hasMediaPreview) {
      return _MediaPreviewCard(
        attachment: attachment,
        busy: busy,
        onDownload: onDownload,
        onCancel: onCancel,
        onOpen: onOpen,
        messageFooter: messageFooter,
      );
    }

    // File branch.
    final l = AppLocalizations.of(context)!;
    final canOpen = attachment.localPath != null;
    final footer = messageFooter;
    final bar = _buildBar(
      l: l,
      fileName: descriptor.fileName,
      totalSize: descriptor.totalSize,
      attachment: attachment,
      action: attachment.transferControl(busy: busy) != null
          ? AttachmentActions(
              attachment: attachment,
              busy: busy,
              onDownload: onDownload,
              onCancel: onCancel,
              l: l,
            )
          : null,
      messageFooter: footer == null
          ? null
          : Padding(
              padding: const EdgeInsetsDirectional.only(
                  end: MoshShapes.attachmentFooterInset),
              child: footer,
            ),
    );
    return _FileCardShell(
      failed: attachment.failed,
      child: AttachmentOpenTarget(
        label: l.attachmentOpenAria(descriptor.fileName),
        onOpen: canOpen ? () => onOpen(descriptor) : null,
        child: Row(
          // Keep metadata and inline time at the icon's lower edge.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AttachmentThumb(
              descriptor: descriptor,
              viewable: attachment.viewable,
              failed: attachment.failed,
              onOpen: canOpen ? null : onOpen,
            ),
            const SizedBox(width: 10),
            Expanded(child: bar),
          ],
        ),
      ),
    );
  }
}

/// Max width of the file card.
const double kAttachmentCardMaxWidth = 360;

/// Fixed width of the media-preview card.
const double kAttachmentMediaWidth = 320;

/// Cap on the preview height; taller media is cropped to cover the box.
const double kAttachmentPreviewMaxHeight = 260;

/// Floor for the same box, so panoramas keep a usable open target.
const double kAttachmentPreviewMinHeight = 120;

/// Height reserved when the miniature does not reveal the media's size.
const double kAttachmentPreviewFallbackHeight = 200;

/// The preview height is fixed before decoding so miniature, clear preview
/// and original swap without moving the message list.
double attachmentPreviewHeight(Size? media,
        {double width = kAttachmentMediaWidth}) =>
    media == null
        ? kAttachmentPreviewFallbackHeight
        : (width * media.height / media.width)
            .clamp(kAttachmentPreviewMinHeight, kAttachmentPreviewMaxHeight);

/// Embedded content shares the message surface. Files are flat rows;
/// media clips to the shared attachment corners. Failed transfers keep an edge.
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
        borderRadius: MoshShapes.attachment,
        border: failed ? Border.all(color: MoshColors.danger) : null,
      ),
      child: child,
    );
  }
}

/// Shared name, metadata and progress for both card branches.
///
/// A transfer button keeps one trailing slot beside the name and metadata,
/// so the message time never moves it. Like text bubbles, the time ends the
/// last line: the progress bar while downloading, otherwise the metadata.
Widget _buildBar({
  required AppLocalizations l,
  required String fileName,
  required BigInt totalSize,
  required ConversationAttachment attachment,
  Widget? action,
  Widget? messageFooter,
}) {
  final progress = attachment.progress;
  final percent = progress?.percent ?? 0;
  final details = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, color: MoshColors.fg1),
      ),
      const SizedBox(height: 2),
      _trailing(
        _attachmentMeta(l, totalSize, attachment.state, percent),
        progress == null ? messageFooter : null,
      ),
    ],
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (action == null)
        details
      else
        Row(children: [
          Expanded(child: details),
          const SizedBox(width: 8),
          action,
        ]),
      if (progress != null) ...[
        const SizedBox(height: 4),
        _trailing(_progressBar(l, progress.fraction, percent), messageFooter),
      ],
    ],
  );
}

/// 4px moss progress on bg-3; a null [fraction] is indeterminate.
Widget _progressBar(AppLocalizations l, double? fraction, int percent) =>
    ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 4,
        backgroundColor: MoshColors.bg3,
        color: MoshColors.moss,
        semanticsLabel: l.attachmentStateDownloading(percent),
      ),
    );

/// [content] fills the line and [footer], when present, ends it.
Widget _trailing(Widget content, Widget? footer) => footer == null
    ? content
    : Row(children: [
        Expanded(child: content),
        const SizedBox(width: 8),
        footer,
      ]);

/// Size only when available; every other state appends " · {label}".
Widget _attachmentMeta(
    AppLocalizations l, BigInt totalSize, AttachmentState state, int percent) {
  final size = formatBytes(totalSize);
  return Text(
    state == AttachmentState.available
        ? size
        : '$size \u00b7 ${_attachmentStateLabel(l, state, percent)}',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
        fontSize: 11,
        color: MoshColors.fg3,
        fontFeatures: kLiveNumberFontFeatures),
  );
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
