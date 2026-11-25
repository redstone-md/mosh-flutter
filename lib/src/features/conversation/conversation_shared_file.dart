import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/features/conversation/conversation_attachment.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/file_card.dart';
import 'package:mosh/src/features/conversation/message_tone.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

/// A row of the shared files in the conversation details: the File card on
/// a surface, whatever the file is. Previews and audio playback stay in the
/// message cards; the row keeps 8 px above and below its card, as a bubble
/// does.
class ConversationSharedFile extends StatelessWidget {
  const ConversationSharedFile({
    super.key,
    required this.message,
    required this.view,
    required this.actions,
  });

  final ConversationMessage message;
  final AttachmentView? view;
  final ConversationAttachmentCallbacks actions;

  @override
  Widget build(BuildContext context) {
    final file = message.attachment!;
    final attachment =
        ConversationAttachment(descriptor: file, view: view, own: message.own);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MoshSpace.s2),
      child: FileCard(
        attachment: attachment,
        tone: MessageTone.of(context, own: false),
        action: attachmentAction(attachment,
            busy: actions.busy,
            l: AppLocalizations.of(context)!,
            onDownload: actions.onDownload,
            onCancel: actions.onCancel,
            onOpen: () => actions.onOpen(file)),
      ),
    );
  }
}
