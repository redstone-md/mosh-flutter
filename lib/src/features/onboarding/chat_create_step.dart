import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/features/onboarding/pending_invitation_card.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show InviteCreated;
import 'package:mosh/src/state/pending_invites_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

class ChatCreateStep extends ConsumerStatefulWidget {
  const ChatCreateStep({super.key, required this.onOpened});

  final ValueChanged<String> onOpened;

  @override
  ConsumerState<ChatCreateStep> createState() => _ChatCreateStepState();
}

class _ChatCreateStepState extends ConsumerState<ChatCreateStep> {
  bool _busy = false;
  bool _creating = false;
  ConversationActionError? _error;

  void _reportError(Object error) {
    if (mounted) setState(() => _error = ConversationActionError.of(error));
  }

  Future<void> _run(Future<void> Function() action,
      {bool creating = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _creating = creating;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _creating = false;
        });
      }
    }
  }

  Future<void> _create() {
    final flow = ref.read(inviteFlowProvider.notifier);
    return _run(() async {
      await flow.create();
    }, creating: true);
  }

  Future<void> _replace(String sessionId) {
    final invitations = ref.read(pendingInvitesProvider.notifier);
    return _run(() async {
      await invitations.replace(sessionId);
    });
  }

  Future<void> _open(String sessionId) {
    final invitations = ref.read(pendingInvitesProvider.notifier);
    final onOpened = widget.onOpened;
    return _run(() async {
      await invitations.open(sessionId);
      if (mounted) onOpened(sessionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pending = ref.watch(pendingInvitesProvider);
    final invites = pending.value ?? const [];
    final error = _error ??
        switch (pending.error) {
          final error? => ConversationActionError.of(error),
          _ => null,
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _createButton(l, hasInvites: invites.isNotEmpty),
        if (error != null) ...[
          const SizedBox(height: 12),
          InlineError(message: error.describe(l)),
        ],
        if (pending.isLoading && !pending.hasValue) ...[
          const SizedBox(height: 20),
          const LinearProgressIndicator(),
        ],
        if (pending.hasError)
          TextButton(
              onPressed: _busy
                  ? null
                  : () =>
                      _run(ref.read(pendingInvitesProvider.notifier).refresh),
              child: Text(l.sessionsRetry)),
        if (invites.isNotEmpty) ..._savedInvitations(l, invites),
      ],
    );
  }

  Widget _createButton(AppLocalizations l, {required bool hasInvites}) =>
      FilledButton.icon(
        onPressed: _busy ? null : _create,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: _creating
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.link, size: 18),
        label: Text(hasInvites ? l.createNewInvitation : l.onboardChatCreate),
      );

  List<Widget> _savedInvitations(
          AppLocalizations l, List<InviteCreated> invites) =>
      [
        const SizedBox(height: 20),
        Text(l.pendingInvitations,
            style: Theme.of(context).textTheme.titleSmall),
        for (final invite in invites) ...[
          const SizedBox(height: 12),
          PendingInvitationCard(
              key: ValueKey(invite.sessionId),
              invite: invite,
              busy: _busy,
              onError: _reportError,
              onReplace: () => _replace(invite.sessionId),
              onOpen: () => _open(invite.sessionId)),
        ],
      ];
}
