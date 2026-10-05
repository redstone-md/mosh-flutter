import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_message_footer.dart';
import 'package:mosh/src/features/conversation/conversation_message_text.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/features/conversation/call_log_entry.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/failed_message_retry.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor, AttachmentView;
import 'package:mosh/src/rust/message_deletion/types.dart';

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
    this.continuesBelow = false,
  });

  final ConversationMessage message;
  final ConversationKind kind;

  /// Whether this row continues the previous sender's block. A continuation
  /// row drops the meta and indents under the first row's avatar.
  final bool grouped;
  final bool continuesBelow;

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
        child: LayoutBuilder(
            builder: (context, constraints) => Row(
                  mainAxisAlignment: message.own
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!message.own) ...[
                      if (grouped)
                        const SizedBox(width: messageAvatarSize)
                      else
                        SelectionContainer.disabled(
                            child: Avatar(
                                name: message.fromDevice,
                                radius: messageAvatarSize / 2)),
                      const SizedBox(width: kMessageRowGap),
                    ],
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: (constraints.maxWidth * 0.78).clamp(
                              0.0,
                              (constraints.maxWidth -
                                      (message.own
                                          ? 0
                                          : messageAvatarSize + kMessageRowGap))
                                  .clamp(0.0, 520.0))),
                      child: Container(
                        key: ValueKey(
                            'message-bubble-${message.messageId ?? message.body}'),
                        padding: _hasRectangularAttachment
                            ? MoshShapes.attachmentPadding
                            : MoshShapes.messagePadding,
                        decoration: BoxDecoration(
                          color: message.own
                              ? MoshColors.outgoingMessage
                              : MoshColors.bg2,
                          borderRadius: _corners,
                        ),
                        child: _body(context),
                      ),
                    ),
                  ],
                )),
      );

  BorderRadiusDirectional get _corners {
    final outer = MoshShapes.message.topLeft;
    final join =
        _hasRectangularAttachment ? outer : MoshShapes.embedded.topLeft;
    return BorderRadiusDirectional.only(
      topStart: !message.own && grouped ? join : outer,
      bottomStart: !message.own && continuesBelow ? join : outer,
      topEnd: message.own && grouped ? join : outer,
      bottomEnd: message.own && continuesBelow ? join : outer,
    );
  }

  bool get _hasRectangularAttachment {
    final attachment = message.attachment;
    return attachment != null && attachment.voice == null;
  }

  Widget _body(BuildContext context) {
    if (message.deletion case final deleted?) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                deleted.administrator == null
                    ? l.messageDeleted
                    : l.messageDeletedByAdmin(deleted.administrator!),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontStyle: FontStyle.italic)),
            Text(
                deleted.status == DeletionStatus.pending
                    ? l.messageDeletionPending
                    : l.messageDeletionConfirmed,
                style: Theme.of(context).textTheme.bodySmall),
          ]);
    }
    final footer = ConversationMessageFooter(message: message, kind: kind);
    final hasFooter = footer.measure(context).height > 0;
    final textOnly = message.body.isNotEmpty &&
        message.attachment == null &&
        message.callEvent == null &&
        !message.canRetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!grouped && !message.own && kind != ConversationKind.dm)
              ConversationSenderMeta(
                fromDevice: message.fromDevice,
                fromFingerprint: message.fromFingerprint,
                sentAtMs: message.sentAtMs,
                showTime: false,
                showMlsBadge: kind != ConversationKind.channel,
                peer: peer,
              ),
            if (message.body.isNotEmpty)
              if (textOnly)
                ConversationMessageText(body: message.body, footer: footer)
              else
                Text(message.body, style: kMessageBodyStyle),
            if (message.body.isNotEmpty && message.attachment != null)
              const SizedBox(height: 6),
            SelectionContainer.disabled(
                child: _trailing(hasFooter ? footer : null)),
          ],
        ),
        if (!textOnly && message.attachment == null && hasFooter)
          Padding(padding: const EdgeInsets.only(top: 4), child: footer),
      ],
    );
  }

  /// Attachment and call controls remain outside text selection.
  Widget _trailing(Widget? footer) {
    final attachment = message.attachment;
    final callEvent = message.callEvent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (attachment != null)
          AttachmentCard(
            descriptor: attachment,
            view: attachmentView,
            own: message.own,
            busy: busy,
            onDownload: onAttachmentDownload,
            onCancel: onAttachmentCancel,
            onOpen: onAttachmentOpen,
            messageFooter: footer,
          ),
        if (callEvent != null) CallLogEntry(event: callEvent, l: l),
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
