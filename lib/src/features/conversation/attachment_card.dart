import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures, moshTonalIconButtonStyle;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/features/conversation/conversation_attachment.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show attachmentWidth;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/conversation/file_card.dart';
import 'package:mosh/src/features/conversation/message_tone.dart';
import 'attachment_preview_image.dart';
import 'package:mosh/src/features/conversation/voice_message_card.dart';

part 'attachment_card_branches.dart';

/// What a message carries above its text, or in place of it: a voice
/// message, a picture or a video with its preview, or any other file. It
/// has no background of its own and takes the inks of the bubble it sits
/// in: [own] for a message the user sent.
///
/// When a transfer view is present the direction comes from it; otherwise
/// [own] stands in, so an own message with no transfer state is a file that
/// is already here.
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

  /// True while another transfer is running, which makes a download wait.
  final bool busy;

  /// The time of a message that is this attachment alone. A file and a
  /// voice message end their last line with it; a picture keeps a line of
  /// its own for it under its name.
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
    final l = AppLocalizations.of(context)!;
    if (descriptor.voice != null) {
      return VoiceMessageCard(
        descriptor: descriptor,
        view: view,
        own: own,
        busy: busy,
        onDownload: onDownload,
        messageFooter: messageFooter,
      );
    }
    final tone = MessageTone.of(context, own: own);
    final action = attachmentAction(attachment,
        busy: busy,
        l: l,
        onDownload: onDownload,
        onCancel: onCancel,
        onOpen: () => onOpen(descriptor));
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: attachmentWidth(compact: isMobileBreakpoint(context))),
      // Images can also preview their downloaded file when no thumbnail
      // arrived.
      child: attachment.hasMediaPreview
          ? _MediaCard(
              attachment: attachment,
              tone: tone,
              action: action,
              onOpen: () => onOpen(descriptor),
              footer: messageFooter)
          : FileCard(
              attachment: attachment,
              tone: tone,
              action: action,
              footer: messageFooter),
    );
  }
}

/// Cap on the preview height; taller media is cropped to cover the box.
const double kAttachmentPreviewMaxHeight = 260;

/// Floor for the same box, so panoramas keep a usable open target.
const double kAttachmentPreviewMinHeight = 120;

/// Height reserved when the miniature does not reveal the media's size:
/// the preview of the Media card, 200 px on the desktop and 148 px in the
/// narrower card of the phone.
double attachmentPreviewFallbackHeight(double width) =>
    width < attachmentWidth(compact: false) ? 148 : 200;

/// The preview height is fixed before decoding so miniature, clear preview
/// and original swap without moving the message list.
double attachmentPreviewHeight(Size? media, {required double width}) =>
    media == null
        ? attachmentPreviewFallbackHeight(width)
        : (width * media.height / media.width)
            .clamp(kAttachmentPreviewMinHeight, kAttachmentPreviewMaxHeight);
