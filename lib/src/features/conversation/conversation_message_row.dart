/// A message bubble with sender actions, attachments and delivery status.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/features/conversation/call_log_entry.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/failed_message_retry.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/conversation/attachments.dart'
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: message.own
                              ? const Color(0xFF25472D)
                              : MoshColors.bg2,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _body(),
                      ),
                    ),
                  ],
                )),
      );

  Widget _body() => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!grouped && !message.own)
                ConversationSenderMeta(
                  fromDevice: message.fromDevice,
                  fromFingerprint: message.fromFingerprint,
                  sentAtMs: message.sentAtMs,
                  showTime: false,
                  showMlsBadge: kind != ConversationKind.channel,
                  peer: peer,
                ),
              if (message.body.isNotEmpty)
                Text(message.body, style: kMessageBodyStyle),
              SelectionContainer.disabled(child: _trailing()),
            ],
          ),
          SelectionContainer.disabled(
              child: _MessageFooter(message: message, kind: kind)),
        ],
      );

  /// Attachment and call controls remain outside text selection.
  Widget _trailing() {
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

class _MessageFooter extends StatelessWidget {
  const _MessageFooter({required this.message, required this.kind});
  final ConversationMessage message;
  final ConversationKind kind;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocalizations.of(context)!.localeName;
    final time = formatClock(message.sentAtMs, locale: locale);
    final full = formatClockFull(message.sentAtMs, locale: locale);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (time != null && full != null)
          Tooltip(message: full, child: Text(time, style: kMessageTimeStyle)),
        if (message.own && kind == ConversationKind.dm) ...[
          const SizedBox(width: 5),
          DeliveryTicks(
              status: message.deliveryStatus,
              read: message.read == true,
              compact: true),
        ],
      ]),
    );
  }
}
