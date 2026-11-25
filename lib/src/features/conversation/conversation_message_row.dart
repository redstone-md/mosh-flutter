import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_message_footer.dart';
import 'package:mosh/src/features/conversation/conversation_message_text.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/conversation/message_bubble.dart';
import 'package:mosh/src/features/conversation/message_tone.dart';
import 'package:mosh/src/features/conversation/call_log_entry.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/failed_message_retry.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor, AttachmentView;
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/features/plus/plus_identity.dart';

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
    this.conversationKey,
    this.continuesBelow = false,
  });

  final ConversationMessage message;
  final ConversationKind kind;
  final String? conversationKey;

  String? get _plusIdentity =>
      verifiedMessagePlusIdentity(message, conversationKey);

  /// Whether this row continues the previous sender's run. A continuation
  /// row drops the sender line and keeps the gutter under the first row's
  /// avatar.
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

  /// Sends a failed message again, where it can be sent again.
  final void Function(String messageId) onRetry;

  final AppLocalizations l;

  /// A group and a channel name the sender; a direct chat has one peer and
  /// shows neither their name nor their avatar beside a message.
  bool get _namesSender => !message.own && kind != ConversationKind.dm;

  @override
  Widget build(BuildContext context) {
    final gutter = _namesSender ? messageAvatarSize + kMessageRowGap : 0.0;
    final failed =
        message.own && message.deliveryStatus == MessageDeliveryStatus.failed;
    return Padding(
      padding: EdgeInsets.only(top: messageRowSpacing(grouped)),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          mainAxisAlignment:
              message.own ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_namesSender) ...[
              // The gutter stays under the avatar of the run's first row.
              if (grouped)
                const SizedBox(width: messageAvatarSize)
              else
                SelectionContainer.disabled(
                    child: Avatar(
                        name: message.fromDevice,
                        plusIdentity: _plusIdentity,
                        radius: messageAvatarSize / 2)),
              const SizedBox(width: kMessageRowGap),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth - gutter)
                      .clamp(0.0, double.infinity)),
              // A failure sits under its bubble, on the bubble's side.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MessageBubble(
                    id: message.messageId ?? message.body,
                    tone: MessageTone.of(context, own: message.own),
                    own: message.own,
                    grouped: grouped,
                    continuesBelow: continuesBelow,
                    gone: message.deletion != null,
                    selectionId: message.messageId,
                    child: _body(context),
                  ),
                  if (failed)
                    SelectionContainer.disabled(
                      child: FailedMessageRetry(
                        deliveryError: message.deliveryError,
                        onRetry: message.canRetry
                            ? () => onRetry(message.messageId!)
                            : null,
                        l: l.toFailedMessageRetryL10n(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A confirmed deletion needs no status line; a pending or refused one does.
  String? _deletionStatus(DeletionStatus status) => switch (status) {
        DeletionStatus.pending => l.messageDeletionPending,
        DeletionStatus.confirmed => null,
        DeletionStatus.rejected => l.messageDeletionLocalOnly,
      };

  Widget _deleted(BuildContext context, DeletionMarker deleted) {
    final text = Theme.of(context).textTheme;
    final quiet = MoshColors.of(context).onSurfaceMuted;
    return Padding(
      padding: MoshShapes.bubbleInset,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                deleted.administrator == null
                    ? l.messageDeleted
                    : l.messageDeletedByAdmin(deleted.administrator!),
                style: text.bodyLarge!.copyWith(color: quiet)),
            if (_deletionStatus(deleted.status) case final status?)
              Text(status, style: text.labelMedium!.copyWith(color: quiet)),
          ]),
    );
  }

  /// What the bubble holds, top to bottom: the sender, a file, a picture or
  /// a voice message, then the text. The time ends the last line of the
  /// text; a file or a voice message alone keeps it in its own last line.
  Widget _body(BuildContext context) {
    if (message.deletion case final deleted?) return _deleted(context, deleted);
    final compact = isMobileBreakpoint(context);
    final footer = ConversationMessageFooter(message: message, kind: kind);
    final hasFooter = footer.measure(context).height > 0;
    final attachment = message.attachment;
    final callEvent = message.callEvent;
    final hasText = message.body.isNotEmpty;
    // Under an attachment the text is a caption and wraps at its width.
    final measure = attachment == null
        ? messageMeasure(compact: compact)
        : attachmentWidth(compact: compact) - MoshShapes.bubbleInset.horizontal;
    Widget inset(Widget child) => Padding(
        padding: MoshShapes.bubbleInset,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: measure), child: child));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: MoshSpace.s1,
          children: [
            if (_namesSender && !grouped)
              inset(ConversationSenderMeta(
                fromDevice: message.fromDevice,
                plusIdentity: _plusIdentity,
                fromFingerprint: message.fromFingerprint,
                peer: peer,
              )),
            // Attachment and call controls remain outside text selection.
            if (attachment != null)
              SelectionContainer.disabled(
                child: AttachmentCard(
                  descriptor: attachment,
                  view: attachmentView,
                  own: message.own,
                  busy: busy,
                  onDownload: onAttachmentDownload,
                  onCancel: onAttachmentCancel,
                  onOpen: onAttachmentOpen,
                  messageFooter: hasText || !hasFooter ? null : footer,
                ),
              ),
            if (callEvent != null)
              SelectionContainer.disabled(
                  child: CallLogEntry(
                      event: callEvent, outgoing: message.own, l: l)),
            if (hasText)
              inset(ConversationMessageText(
                  body: message.body, footer: footer, own: message.own)),
          ],
        ),
        if (!hasText && attachment == null && hasFooter) inset(footer),
      ],
    );
  }
}
