import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/features/conversation/conversation_shared_file.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_details_model.dart';
import 'package:mosh/src/features/conversation/conversation_diagnostics_content.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';

/// The same content is docked on desktop and placed in the modal on mobile.
class ConversationDetailsPanel extends ConsumerWidget {
  const ConversationDetailsPanel({
    super.key,
    required this.target,
    required this.async,
    required this.onClose,
    required this.onOpenAttachment,
  });

  final AnyConversationTarget target;
  final AsyncValue<ConversationSnapshot> async;
  final VoidCallback onClose;
  final void Function(AttachmentDescriptor, AttachmentView?) onOpenAttachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: MoshColors.bg1,
      child: Column(
        children: [
          SizedBox(
            height: 70,
            child: Row(children: [
              const SizedBox(width: 20),
              Expanded(child: Text(l.chatDetailsTitle)),
              IconButton(
                  onPressed: onClose,
                  tooltip: l.dialogClose,
                  icon: const Icon(Icons.close, size: 20)),
              const SizedBox(width: 8),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
              child: async.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child:
                        Text(ConversationActionError.of(error).describe(l)))),
            data: (snapshot) => _content(context, ref, snapshot, l),
          )),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref,
      ConversationSnapshot snapshot, AppLocalizations l) {
    final model = ConversationDetailsModel(snapshot, l);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _profile(context, model),
        const SizedBox(height: 28),
        _protection(model, l),
        _participants(model, l),
        _Section(
            title: l.chatDetailsFiles, child: _files(ref, snapshot, model, l)),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(l.chatDetailsDiagnostics),
          children: [
            TextButton.icon(
                onPressed: ref
                    .read(conversationControllerProvider(target).notifier)
                    .refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l.refreshStatus)),
            ConversationDiagnosticsContent(
              session: snapshot is DmConversation ? snapshot.source : null,
              group: snapshot is GroupConversation ? snapshot.source : null,
              channel: snapshot is ChannelConversation ? snapshot.source : null,
              error: null,
              scrollable: false,
            )
          ],
        ),
      ],
    );
  }

  Widget _profile(BuildContext context, ConversationDetailsModel model) =>
      Column(children: [
        ConversationKindAvatar(
            kind: target.kind, name: model.title, radius: 38),
        const SizedBox(height: 14),
        Text(model.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(model.subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ]);

  Widget _protection(ConversationDetailsModel model, AppLocalizations l) =>
      _Section(
          title: l.chatDetailsProtection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(model.protection,
                  style: TextStyle(
                      color: model.needsAttention
                          ? MoshColors.danger
                          : model.snapshot is ChannelConversation
                              ? MoshColors.fg2
                              : MoshColors.moss,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(model.protectionBody),
            ],
          ));

  Widget _participants(ConversationDetailsModel model, AppLocalizations l) =>
      _Section(
        title: model.knownAuthorsOnly
            ? l.chatDetailsKnownAuthors
            : l.chatDetailsParticipants,
        child: Column(children: [
          for (final participant in model.participants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Avatar(name: participant.name, radius: 17),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(participant.name,
                        overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ]),
      );

  Widget _files(WidgetRef ref, ConversationSnapshot snapshot,
      ConversationDetailsModel model, AppLocalizations l) {
    final files = model.files;
    if (files.isEmpty) return Text(l.chatDetailsNoFiles);
    ref.watch(
        conversationControllerProvider(target).select((s) => s.transferBusy));
    final actions = ref
        .read(conversationControllerProvider(target).notifier)
        .attachmentCallbacks(onOpenAttachment);
    final views = {for (final v in snapshot.attachments) v.attachmentId: v};
    final cards = <Widget>[];
    for (final message in files) {
      final descriptor = message.attachment!;
      final view = views[descriptor.attachmentId];
      final callbacks = actions(view);
      cards.add(ConversationSharedFile(
          message: message, view: view, actions: callbacks));
    }
    return Column(children: cards);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          child,
        ]),
      );
}
