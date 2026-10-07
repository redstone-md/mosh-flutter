import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider;
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';

class ChatCreateStep extends ConsumerStatefulWidget {
  const ChatCreateStep({super.key});

  @override
  ConsumerState<ChatCreateStep> createState() => _ChatCreateStepState();
}

class _ChatCreateStepState extends ConsumerState<ChatCreateStep> {
  bool _busy = false;
  bool _copied = false;
  // Persistent inline error -- stays until the next create attempt.
  // Cleared at the START of the next attempt below.
  ConversationActionError? _error;

  Future<void> _onCreate() async {
    if (_busy) return;
    // Reset `copied` whenever a new create begins; the previous invite's
    // "Copied" badge should not persist onto a fresh link.
    setState(() {
      _busy = true;
      _copied = false;
      _error = null;
    });
    try {
      await ref.read(inviteFlowProvider.notifier).create();
      await ref
          .read(conversationListProvider(ConversationKind.dm).notifier)
          .refresh();
    } catch (e) {
      // The inline error is the one source of truth (no SnackBar), and its
      // wording comes from the bridge kind when the seam threw one.
      if (mounted) setState(() => _error = ConversationActionError.of(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onCopy(String uri) async {
    final toaster = context.toaster;
    final copied = AppLocalizations.of(context)!.messageCopied;
    await Clipboard.setData(ClipboardData(text: uri));
    toaster.show(copied, kind: ToastKind.success);
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final lastInvite = ref.watch(inviteFlowProvider).lastInvite;
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: InlineError(message: _error?.describe(l)),
          );
    if (lastInvite == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _onCreate,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: _busy ? const _Spinner() : const Icon(Icons.link, size: 18),
            label: Text(l.onboardChatCreate),
          ),
          if (error != null) error,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InviteResult(
          note: l.onboardInviteReady,
          uri: lastInvite.inviteUri,
          copied: _copied,
          onCopy: () => _onCopy(lastInvite.inviteUri),
          onReplace: _onCreate,
          replaceLabel: l.onboardChatRecreate,
          openLabel: l.onboardOpenChat,
          onOpen: () => context.go(AppRoutes.dmFor(lastInvite.sessionId)),
          footer: l.onboardInviteFooter,
        ),
        if (error != null) error,
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
