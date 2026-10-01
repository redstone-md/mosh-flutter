import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/features/conversation/attachment_thumb.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/util/format.dart' show formatBytes;

/// Compact file index. Previews and audio playback stay in the message cards;
/// this row reuses their transfer actions without creating another media player.
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
    final l = AppLocalizations.of(context)!;
    final file = message.attachment!;
    final outgoing =
        view?.direction == 'outgoing' || (view == null && message.own);
    final state = view?.state ??
        (outgoing ? AttachmentState.available : AttachmentState.offered);
    final canOpen = state == AttachmentState.available &&
        (view?.localPath?.isNotEmpty ?? false);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AttachmentOpenTarget(
        label: l.attachmentOpenAria(file.fileName),
        onOpen: canOpen ? () => actions.onOpen(file) : null,
        child: Row(children: [
          Container(
            width: kAttachmentThumbSize,
            height: kAttachmentThumbSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: MoshColors.mossGlow, borderRadius: MoshShapes.control),
            child: const Icon(Icons.insert_drive_file_outlined,
                color: MoshColors.moss300, size: 23),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                  message: file.fileName,
                  child: Text(file.fileName,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(height: 4),
              Text(formatBytes(file.totalSize),
                  style: Theme.of(context).textTheme.bodySmall),
              if (state == AttachmentState.downloading)
                LinearProgressIndicator(
                    value: view!.chunkCount == BigInt.zero
                        ? null
                        : (view!.completedChunks.toDouble() /
                                view!.chunkCount.toDouble())
                            .clamp(0.0, 1.0)),
            ],
          )),
          AttachmentActions(
            descriptor: file,
            state: state,
            outgoing: outgoing,
            busy: actions.busy,
            onDownload: actions.onDownload,
            onCancel: actions.onCancel,
            l: l,
          ),
        ]),
      ),
    );
  }
}
