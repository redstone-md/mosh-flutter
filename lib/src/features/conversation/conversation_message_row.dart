/// One message row, for any kind of conversation.
///
/// The layout is the same everywhere: an avatar (a spacer on a continuation
/// row), then the sender meta, the text, the attachment card, and whatever
/// the message trails with. Rows are always left-aligned; `own` only decides
/// whether the delivery state and the Retry button show.
///
/// Three small parts follow the kind:
///
/// - a DM has no fingerprint chip in the meta and shows delivery ticks;
/// - a channel hides the MLS badge;
/// - only a DM can carry a call log entry.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/features/dm/call_log_entry.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/failed_message_retry.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentDescriptor, AttachmentView;

class ConversationMessageRow extends StatelessWidget {
  const ConversationMessageRow({
    super.key,
    required this.message,
    required this.kind,
    required this.grouped,
    required this.busy,
    required this.onAttachmentDownload,
    required this.onAttachmentCancel,
    required this.onAttachmentOpen,
    required this.onRetry,
    required this.l,
    this.attachmentView,
    this.peer,
  });

  final ConversationMessage message;
  final ConversationKind kind;

  /// Whether this row continues the previous sender's block. A continuation
  /// row drops the meta and indents under the first row's avatar.
  final bool grouped;

  final AttachmentView? attachmentView;

  /// Makes the sender name tappable so the user can start a DM with them.
  /// Null in a DM, where there is only one peer and it is already open.
  final PeerActions? peer;

  /// True while another transfer is running, which disables the card's
  /// download and retry buttons.
  final bool busy;

  final void Function(String attachmentId) onAttachmentDownload;
  final void Function(String attachmentId) onAttachmentCancel;
  final void Function(AttachmentDescriptor descriptor) onAttachmentOpen;

  /// Sends a failed message again.
  final void Function(String messageId) onRetry;

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: messageRowSpacing(grouped)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A continuation row leaves the avatar's width empty, so it
            // lines up under the first row of the block.
            if (grouped)
              const SizedBox(width: messageAvatarSize)
            else
              Avatar(name: message.fromDevice, radius: messageAvatarSize / 2),
            const SizedBox(width: kMessageRowGap),
            Expanded(child: _body()),
          ],
        ),
      );

  /// The meta, the text, and whatever the message trails with.
  Widget _body() {
    final attachment = message.attachment;
    final callEvent = message.callEvent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!grouped)
          ConversationSenderMeta(
            fromDevice: message.fromDevice,
            fromFingerprint: message.fromFingerprint,
            sentAtMs: message.sentAtMs,
            showMlsBadge: kind != ConversationKind.channel,
            peer: peer,
          ),
        if (message.body.isNotEmpty)
          Text(message.body, style: kMessageBodyStyle),
        if (attachment != null)
          AttachmentCard(
            descriptor: attachment,
            view: attachmentView,
            own: message.own,
            busy: busy,
            onDownload: onAttachmentDownload,
            onCancel: onAttachmentCancel,
            onOpen: onAttachmentOpen,
          ),
        if (callEvent != null) CallLogEntry(event: callEvent, l: l),
        if (message.own && kind == ConversationKind.dm)
          DeliveryTicks(status: message.deliveryStatus),
        if (message.canRetry)
          FailedMessageRetry(
            deliveryError: message.deliveryError,
            onRetry: () => onRetry(message.messageId!),
            l: l.toFailedMessageRetryL10n(),
          ),
      ],
    );
  }
}
