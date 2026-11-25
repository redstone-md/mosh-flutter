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
import 'package:mosh/src/features/conversation/message_selection.dart';
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
    this.conversationId,
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

  /// The conversation's id, which a call in the feed of a DM rings back.
  final String? conversationId;

  final AppLocalizations l;

  /// A group and a channel name the sender; a direct chat has one peer and
  /// shows neither their name nor their avatar beside a message.
  bool get _namesSender => !message.own && kind != ConversationKind.dm;

  @override
  Widget build(BuildContext context) {
    final gutter = _namesSender ? messageAvatarSize + kMessageRowGap : 0.0;
    return LayoutBuilder(
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
            child: _bubbleAndFailure(context),
          ),
        ],
      ),
    );
  }

  /// The ink of what sits straight on the band of a picked row, in place of
  /// inks made for the feed's background that read too faintly there; null
  /// while the row is not picked.
  Color? _onBand(BuildContext context) {
    final id = message.messageId;
    final selection = MessageSelectionScope.maybeOf(context)?.selection;
    return id != null && (selection?.isSelected(id) ?? false)
        ? MoshColors.of(context).onSecondaryContainer
        : null;
  }

  /// The bubble, or the call that is a bubble of its own, and under it, on
  /// the same side, the notice of a message that was not sent.
  Widget _bubbleAndFailure(BuildContext context) {
    final failed =
        message.own && message.deliveryStatus == MessageDeliveryStatus.failed;
    final onBand = _onBand(context);
    final tone = MessageTone.of(context, own: message.own);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.callEvent case final call?)
          SelectionContainer.disabled(
            child: CallLogEntry(
                event: call,
                outgoing: message.own,
                sentAtMs: message.sentAtMs,
                conversationId: conversationId,
                l: l),
          )
        else
          MessageBubble(
            id: message.messageId ?? message.body,
            tone: tone,
            grouped: grouped,
            continuesBelow: continuesBelow,
            gone: message.deletion != null,
            child: _body(context, tone, onBand),
          ),
        if (failed)
          SelectionContainer.disabled(
            child: FailedMessageRetry(
              deliveryError: message.deliveryError,
              noticeColor: onBand,
              onRetry:
                  message.canRetry ? () => onRetry(message.messageId!) : null,
              l: l.toFailedMessageRetryL10n(),
            ),
          ),
      ],
    );
  }

  /// What the bubble holds, top to bottom: the sender, a file, a picture or
  /// a voice message, then the text. The time ends the last line of the
  /// text; an attachment alone places it itself.
  Widget _body(BuildContext context, MessageTone tone, Color? onBand) {
    if (message.deletion case final deleted?) {
      return _DeletedNote(deleted: deleted, l: l, ink: onBand);
    }
    final compact = isMobileBreakpoint(context);
    final footer = ConversationMessageFooter(message: message, kind: kind);
    final hasFooter = footer.measure(context).height > 0;
    final attachment = message.attachment;
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
      spacing: MoshSpace.s1,
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
            if (attachment != null)
              _attachmentCard(
                  attachment, hasText || !hasFooter ? null : footer),
            if (hasText)
              inset(ConversationMessageText(
                  body: message.body, footer: footer, tone: tone)),
          ],
        ),
        if (!hasText && attachment == null && hasFooter) inset(footer),
      ],
    );
  }

  /// The controls of an attachment remain outside text selection.
  Widget _attachmentCard(AttachmentDescriptor attachment, Widget? footer) =>
      SelectionContainer.disabled(
        child: AttachmentCard(
          descriptor: attachment,
          view: attachmentView,
          own: message.own,
          busy: busy,
          onDownload: onAttachmentDownload,
          onCancel: onAttachmentCancel,
          onOpen: onAttachmentOpen,
          // The time keeps the text's inset from the bubble's edge.
          messageFooter: footer == null
              ? null
              : Padding(
                  padding: EdgeInsetsDirectional.only(
                      end: MoshShapes.bubbleInset.end),
                  child: footer),
        ),
      );
}

/// What stands in the outlined bubble of a deleted message: that it was
/// deleted and by whom, and, unless the deletion is confirmed, where it
/// stands.
class _DeletedNote extends StatelessWidget {
  const _DeletedNote({required this.deleted, required this.l, this.ink});

  /// The ink on the band of a picked row; the feed's muted one otherwise.
  final Color? ink;
  final DeletionMarker deleted;
  final AppLocalizations l;

  /// A confirmed deletion needs no status line; a pending or refused one does.
  String? get _status => switch (deleted.status) {
        DeletionStatus.pending => l.messageDeletionPending,
        DeletionStatus.confirmed => null,
        DeletionStatus.rejected => l.messageDeletionLocalOnly,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final quiet = ink ?? MoshColors.of(context).onSurfaceMuted;
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
            if (_status case final status?)
              Text(status, style: text.labelMedium!.copyWith(color: quiet)),
          ]),
    );
  }
}
