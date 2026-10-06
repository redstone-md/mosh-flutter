import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/message_selection_host.dart';
import 'package:mosh/src/state/conversation_providers.dart';

/// Serves [snapshot] as the conversation the screen's selection reads.
Override hostedSnapshotOverride(
        ValueListenable<ConversationSnapshot> snapshot) =>
    conversationSnapshotProvider.overrideWith((ref, target) async {
      void refresh() => ref.invalidateSelf();
      snapshot.addListener(refresh);
      ref.onDispose(() => snapshot.removeListener(refresh));
      return snapshot.value;
    });

/// A bare message list inside the screen's selection host, without the rest
/// of the screen. Pair it with [hostedSnapshotOverride].
class HostedMessageList extends StatelessWidget {
  const HostedMessageList({super.key, required this.snapshot});
  final ValueListenable<ConversationSnapshot> snapshot;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ConversationSnapshot>(
          valueListenable: snapshot,
          builder: (context, current, _) => MessageSelectionHost(
              target: current.target,
              search: '',
              filter: ConversationFilter.all,
              header: const SizedBox.shrink(),
              builder: (context, header) => Scaffold(
                    appBar: PreferredSize(
                        preferredSize: const Size.fromHeight(56),
                        child: header),
                    body: ConversationMessageListView(
                      messages: current.messages,
                      snapshot: current,
                      attachmentCallbacks: (view, {required bool own}) =>
                          ConversationAttachmentCallbacks(
                        busy: false,
                        onDownload: (_) {},
                        onCancel: (_) {},
                        onOpen: (_) {},
                      ),
                      onRetryMessage: (_) {},
                    ),
                  )));
}
