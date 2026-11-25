import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show formatClockFull;
import 'package:mosh/src/features/shared/media_viewer.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/state/conversation_providers.dart';

/// Opens the media viewer on an attachment of the conversation [target]: its
/// bar says who sent the file and when, and Save finds the file where it is
/// at the press, so a video opened while it streamed can be saved once it
/// has arrived. Two messages may carry one attachment, so [own] picks the
/// one that was pressed.
void showConversationMedia(
  BuildContext context,
  WidgetRef ref,
  AnyConversationTarget target,
  AttachmentDescriptor descriptor,
  String src, {
  bool? own,
}) {
  final l = AppLocalizations.of(context)!;
  final id = descriptor.attachmentId;
  final snapshot = conversationSnapshotProvider(target);
  final message = ref
      .read(snapshot)
      .value
      ?.messages
      .where((m) =>
          m.attachment?.attachmentId == id && (own == null || m.own == own))
      .firstOrNull;
  final sent = message == null
      ? null
      : [
          message.own ? l.chatListYou : message.fromDevice,
          formatClockFull(message.sentAtMs, locale: l.localeName),
        ].nonNulls.join(', ');
  // The container outlives the screen the viewer was opened from.
  final container = ProviderScope.containerOf(context, listen: false);
  showMediaViewer(
    context: context,
    descriptor: descriptor,
    src: src,
    sent: sent,
    localPath: () => container
        .read(snapshot)
        .value
        ?.attachments
        .where((a) => a.attachmentId == id)
        .firstOrNull
        ?.localPath,
  );
}
