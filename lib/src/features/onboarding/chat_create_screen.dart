// Chat-create step, 1-в-1 with the React `ChatCreateStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx). Mirrors the React
// flow: a step frame (OnboardStepFrame) with the chat title, a body
// paragraph, a Create/Recreate button (label flips once an invite
// exists), and an `InviteResult` card shown only after the first
// successful create.
//
// Scope (this atomic): the chat-create step ONLY. The group / join /
// channel steps are deferred (they will compose the same
// `OnboardStepFrame` + `InviteResult` primitives when they land).
//
// State split (ADR 0010): the invite URI itself is server-derived state
// read from `inviteFlowProvider.lastInvite` (the `create()` call stores
// it there). Only the local `_busy` (create in flight) and `_copied`
// (just-copied) flags are widget-local -- these are ephemeral UI state,
// exactly the shape of React's local `createState` plus a busy flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/session_providers.dart';

/// The chat-create step screen.
///
/// Reached from the onboarding Chat tile (`context.go(AppRoutes.chatCreate)`).
/// Tapping Create calls `inviteFlowProvider.create()`; the resulting URI is
/// stored on the provider (`lastInvite`) and rendered via [InviteResult].
/// Back returns to the onboarding menu (`AppRoutes.onboarding`).
class ChatCreateScreen extends ConsumerStatefulWidget {
  const ChatCreateScreen({super.key});

  @override
  ConsumerState<ChatCreateScreen> createState() => _ChatCreateScreenState();
}

class _ChatCreateScreenState extends ConsumerState<ChatCreateScreen> {
  bool _busy = false;
  bool _copied = false;

  Future<void> _onCreate() async {
    if (_busy) return;
    // React resets `copied` whenever a new create begins; the previous
    // invite's "Copied" badge should not persist onto a fresh link.
    setState(() {
      _busy = true;
      _copied = false;
    });
    try {
      await ref.read(inviteFlowProvider.notifier).create();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onCopy(String uri) async {
    await Clipboard.setData(ClipboardData(text: uri));
    if (mounted) setState(() => _copied = true);
  }

  void _onBack() => context.go(AppRoutes.onboarding);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final lastInvite = ref.watch(inviteFlowProvider).lastInvite;
    final hasInvite = lastInvite != null;
    return OnboardStepFrame(
      title: l.onboardTileChatTitle,
      onBack: _onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.onboardChatStepBody,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _onCreate,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(hasInvite ? l.onboardChatRecreate : l.onboardChatCreate),
          ),
          if (hasInvite) ...[
            const SizedBox(height: 20),
            InviteResult(
              note: l.onboardInviteReady,
              uri: lastInvite.inviteUri,
              copied: _copied,
              onCopy: () => _onCopy(lastInvite.inviteUri),
            ),
          ],
        ],
      ),
    );
  }
}
