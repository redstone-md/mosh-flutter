import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/connection_status_panel.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_details_model.dart';
import 'package:mosh/src/features/conversation/conversation_shared_file.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/panel_head.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_dialog.dart';
import 'package:mosh/src/features/shared/start_row.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/features/shared/mosh_disclosure.dart';
import 'package:mosh/src/features/shared/value_row.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show DmSessionState;
import 'package:mosh/src/state/chat_names_provider.dart';

/// The Details panel card: who is in the conversation, what was shared, how
/// it is encrypted and how it is connected. Docked beside the conversation
/// on the desktop and a screen of its own in a narrow window. Connection
/// status opens in its place and closes back to it.
class ConversationDetailsPanel extends ConsumerStatefulWidget {
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
  final void Function(AttachmentDescriptor, AttachmentView?, bool own)
      onOpenAttachment;

  @override
  ConsumerState<ConversationDetailsPanel> createState() =>
      _ConversationDetailsPanelState();
}

class _ConversationDetailsPanelState
    extends ConsumerState<ConversationDetailsPanel> {
  bool _status = false;

  AnyConversationTarget get _target => widget.target;

  @override
  void didUpdateWidget(covariant ConversationDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The docked panel is reused for the next conversation, which opens on
    // its details, not on the status the last one was showing.
    if (widget.target != oldWidget.target) _status = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = widget.async;
    if (_status) return _connectionStatus(l);
    return Material(
      color: MoshColors.of(context).surfaceContainerLow,
      child: Column(
        children: [
          PanelHead(title: l.chatDetailsTitle, actions: [
            IconButton(
                onPressed: widget.onClose,
                tooltip: l.dialogClose,
                icon: const Icon(MoshIcons.close)),
          ]),
          Expanded(
              child: async.when(
            skipLoadingOnReload: true,
            loading: () => const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                    padding: EdgeInsets.symmetric(vertical: MoshSpace.s12),
                    child: CircularProgressIndicator())),
            error: (error, stack) => Center(
                child: Padding(
                    padding: const EdgeInsets.all(MoshSpace.s5),
                    child:
                        Text(ConversationActionError.of(error).describe(l)))),
            data: (snapshot) => _content(snapshot, l),
          )),
        ],
      ),
    );
  }

  Widget _connectionStatus(AppLocalizations l) {
    final async = widget.async;
    final snapshot = async.value;
    return ConnectionStatusPanel(
      session: snapshot is DmConversation ? snapshot.source : null,
      channel: snapshot is ChannelConversation ? snapshot.source : null,
      group: snapshot is GroupConversation ? snapshot.source : null,
      error: async.hasError
          ? ConversationActionError.of(async.error!).describe(l)
          : null,
      refreshing: async.isLoading,
      onRefresh:
          ref.read(conversationControllerProvider(_target).notifier).refresh,
      onClose: () => setState(() => _status = false),
    );
  }

  Widget _content(ConversationSnapshot snapshot, AppLocalizations l) {
    final model = ConversationDetailsModel(snapshot, l,
        personalName: ref.watch(personalChatNameProvider(_target.ref)));
    final sections = [
      _profile(model),
      _Section(
          title: model.knownAuthorsOnly
              ? l.chatDetailsKnownAuthors
              : l.chatDetailsParticipants,
          inset: MoshSpace.s1,
          child: Column(children: [
            for (final participant in model.participants)
              _MemberRow(
                  participant: participant,
                  conversation: _target.key,
                  admin: participant.own && model.ownAdmin),
          ])),
      _Section(
          title: l.chatDetailsFiles,
          inset: MoshSpace.s4,
          child: _files(snapshot, model, l)),
      if (model.fingerprint case final fingerprint?)
        _encryption(fingerprint, snapshot is GroupConversation, l),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s1),
          child: _connection(snapshot, l)),
    ];
    // A column, not a lazy list: a handful of sections, and what is under
    // the fold stays reachable by keyboard and by screen readers.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          MoshSpace.s1, MoshSpace.s2, MoshSpace.s1, MoshSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, section) in sections.indexed) ...[
            if (i > 0) const SizedBox(height: MoshSpace.s6),
            section,
          ],
        ],
      ),
    );
  }

  /// The one place a conversation shows its encryption: the row opens the
  /// fingerprint to compare.
  Widget _encryption(String fingerprint, bool group, AppLocalizations l) =>
      StartRow(
        icon: MoshIcons.lock,
        accent: MoshColors.of(context).primary,
        title: l.cryptoNoticeTitle,
        line: l.chatDetailsEncryptionLine,
        onTap: () => showFingerprintDialog(context,
            fingerprint: fingerprint,
            hint: group ? l.groupFingerprintHint : l.inviteFingerprintHint),
      );

  Widget _profile(ConversationDetailsModel model) {
    final text = Theme.of(context).textTheme;
    return Column(children: [
      ConversationKindAvatar(
          kind: _target.kind,
          plusIdentity:
              _target.kind == ConversationKind.dm ? _target.key : null,
          name: model.title,
          radius: MoshSpace.s8,
          online: switch (model.snapshot) {
            DmConversation(:final source) =>
              source.state == DmSessionState.connected,
            _ => false,
          }),
      const SizedBox(height: MoshSpace.s3),
      Text(model.title, textAlign: TextAlign.center, style: text.headlineSmall),
      if (model.personalName != null)
        Text(model.l.chatOriginalName(model.originalName),
            textAlign: TextAlign.center, style: text.bodySmall),
      const SizedBox(height: MoshSpace.s1),
      Text(model.subtitle, textAlign: TextAlign.center, style: text.bodySmall),
    ]);
  }

  Widget _files(ConversationSnapshot snapshot, ConversationDetailsModel model,
      AppLocalizations l) {
    final files = model.files;
    if (files.isEmpty) {
      return Text(l.chatDetailsNoFiles,
          style: Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(color: MoshColors.of(context).onSurfaceMuted));
    }
    ref.watch(
        conversationControllerProvider(_target).select((s) => s.transferBusy));
    final actions = ref
        .read(conversationControllerProvider(_target).notifier)
        .attachmentCallbacks(widget.onOpenAttachment);
    final views = {for (final v in snapshot.attachments) v.attachmentId: v};
    return Column(children: [
      for (final message in files)
        ConversationSharedFile(
            message: message,
            view: views[message.attachment!.attachmentId],
            actions: actions(views[message.attachment!.attachmentId],
                own: message.own)),
    ]);
  }

  /// The readings a person can take in at a glance; the rest is one press
  /// away in connection status.
  Widget _connection(ConversationSnapshot snapshot, AppLocalizations l) {
    final summary = diagnosticsSummary(
        l: l,
        session: snapshot is DmConversation ? snapshot.source : null,
        channel: snapshot is ChannelConversation ? snapshot.source : null,
        group: snapshot is GroupConversation ? snapshot.source : null);
    return MoshDisclosure(
      label: l.chatDetailsDiagnostics,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s3),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueRow(label: l.chatDetailsStatus, value: summary.state),
              for (final fact in summary.facts)
                ValueRow(label: fact.label, value: fact.value),
              TextButton(
                  onPressed: () => setState(() => _status = true),
                  child: Text(l.chatDetailsOpenStatus)),
            ]),
      ),
    );
  }
}

/// A titled part of the panel. Everything in the panel starts on one line,
/// 20 px in: a text stands on it, and a row that is pressed reaches past it
/// by its own padding, so [inset] is what is left for the content to add.
class _Section extends StatelessWidget {
  const _Section(
      {required this.title, required this.inset, required this.child});
  final String title;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s4),
            child: Semantics(
                header: true,
                child: Text(title,
                    style: Theme.of(context).textTheme.titleSmall))),
        const SizedBox(height: MoshSpace.s2),
        Padding(padding: EdgeInsets.symmetric(horizontal: inset), child: child),
      ]);
}

/// The Member row card without its peer line: the compact avatar and the
/// name, and the admin's mark on the row of a group's admin.
class _MemberRow extends StatelessWidget {
  const _MemberRow(
      {required this.participant,
      required this.conversation,
      required this.admin});
  final ConversationParticipant participant;
  final String conversation;
  final bool admin;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(
            minHeight: MoshControl.height(Theme.of(context).platform)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: MoshSpace.s3, vertical: MoshSpace.s1),
          child: Row(children: [
            Avatar(
                name: participant.name,
                ownPlus: participant.authenticated && participant.own,
                plusIdentity: participant.authenticated
                    ? '$conversation:${participant.identity}'
                    : null),
            const SizedBox(width: MoshSpace.s3),
            Expanded(
                child: Text(
                    participant.own
                        ? AppLocalizations.of(context)!
                            .ownMemberName(participant.name)
                        : participant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge)),
            if (admin)
              Tooltip(
                  message: AppLocalizations.of(context)!.groupAdminBadge,
                  child: const Icon(MoshIcons.admin, size: MoshSpace.s4)),
          ]),
        ),
      );
}
