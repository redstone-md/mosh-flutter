import 'package:flutter/widgets.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentState;
import 'package:mosh/src/util/format.dart' show formatBytes;
import 'conversation_attachment.dart';

/// The one thing that can be done with an attachment now, as its card
/// shows and performs it: the glyph on the plate, the short [tooltip], the
/// full [label] for a screen reader, which names the file, and what a press
/// does. [onPressed] is null while the action has to wait for another
/// transfer. [opens] tells opening the file from acting on its transfer.
typedef AttachmentAction = ({
  bool opens,
  IconData glyph,
  String tooltip,
  String label,
  VoidCallback? onPressed,
});

/// The glyph of a file at rest: a picture and anything that plays say so on
/// the plate.
IconData attachmentGlyph(ConversationAttachment attachment) =>
    !attachment.viewable
        ? MoshIcons.file
        : attachment.descriptor.mime.startsWith('image/')
            ? MoshIcons.image
            : MoshIcons.play;

/// What [attachment] offers now, or null when there is nothing to do with
/// it. An incoming file is downloaded, and its transfer stopped, picked up
/// again or tried again; a file that is here is opened. Media that can play
/// before it has arrived opens straight away, which also starts its
/// download.
AttachmentAction? attachmentAction(
  ConversationAttachment attachment, {
  required bool busy,
  required AppLocalizations l,
  required void Function(String attachmentId) onDownload,
  required void Function(String attachmentId) onCancel,
  required VoidCallback onOpen,
}) {
  final file = attachment.descriptor;
  final name = file.fileName;
  final open = (
    opens: true,
    glyph: attachmentGlyph(attachment),
    tooltip: l.attachmentOpenAria(name),
    label: l.attachmentOpenAria(name),
    onPressed: onOpen,
  );
  final control = attachment.transferControl(busy: busy);
  if (control == null) return attachment.localPath == null ? null : open;
  if (control.action == AttachmentTransferAction.download &&
      attachment.viewable) {
    return open;
  }
  final (glyph, tooltip, label) = switch (control.action) {
    AttachmentTransferAction.download => (
        MoshIcons.download,
        l.attachmentDownload,
        l.attachmentDownloadAria(name)
      ),
    AttachmentTransferAction.resumeDownload => (
        MoshIcons.download,
        l.attachmentResumeDownload,
        l.attachmentResumeDownloadAria(name)
      ),
    AttachmentTransferAction.retryDownload => (
        MoshIcons.refresh,
        l.attachmentRetryDownload,
        l.attachmentRetryDownloadAria(name)
      ),
    AttachmentTransferAction.retry => (
        MoshIcons.refresh,
        l.attachmentRetry,
        l.attachmentRetryAria(name)
      ),
    AttachmentTransferAction.cancel => (
        MoshIcons.close,
        l.attachmentCancelDownload,
        l.attachmentCancelDownloadAria(name)
      ),
  };
  return (
    opens: false,
    glyph: glyph,
    tooltip: tooltip,
    label: label,
    onPressed: !control.enabled
        ? null
        : control.action == AttachmentTransferAction.cancel
            ? () => onCancel(file.attachmentId)
            : () => onDownload(file.attachmentId),
  );
}

/// The line under an attachment's name: its size, how far its transfer has
/// come, or why there is none.
String attachmentDetail(ConversationAttachment attachment, AppLocalizations l,
    {String? failed}) {
  final size =
      formatBytes(attachment.descriptor.totalSize, locale: l.localeName);
  return switch (attachment.state) {
    AttachmentState.available || AttachmentState.offered => size,
    AttachmentState.downloading =>
      l.attachmentProgressOf(attachment.progress?.percent ?? 0, size),
    AttachmentState.paused => l.attachmentStatePaused,
    AttachmentState.cancelled => l.attachmentStateCancelled,
    AttachmentState.failed => failed ?? l.attachmentStateFailed,
  };
}
