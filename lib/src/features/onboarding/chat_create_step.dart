// Embeddable chat-create step body -- 1:1 with React `ChatCreateStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx). Renders the step
// CONTENT ONLY: the body paragraph, the Create/Recreate button (label
// flips once an invite exists), InlineError, and InviteResult. NO frame,
// NO back affordance, NO title -- the caller wraps this in the frame
// (OnboardStepFrame for the full-screen route, OnboardStepBody when the
// desktop chat-pane composes it inline in atomic #8). One step content,
// two frames -- DRY, matching atomic #1/#2 (OnboardStepBody/OnboardMenu).
//
// State split (ADR 0010): the invite URI is server-derived state read from
// `inviteFlowProvider.lastInvite` (the `create()` call stores it there).
// Only the local `_busy` (create in flight) and `_copied` (just-copied)
// flags are widget-local -- ephemeral UI state, the shape of React's
// local `createState` plus a busy flag.
//
// `onBack` is an injected VoidCallback (1:1 with React `props.onBack`)
// reserved for caller parity. The step body itself renders no back
// affordance -- the framing widget (OnboardStepFrame/OnboardStepBody)
// owns the Back button and wires it to the same callback the caller
// passes here. The step does NOT context.go itself; the caller decides
// routing (route navigation for ChatCreateScreen, inline step-switch for
// the chat-pane in atomic #8).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/util/format.dart' show readableError;

/// Embeddable chat-create step body -- the step CONTENT only.
///
/// Renders the body paragraph, the Create/Recreate button (label flips
/// once `inviteFlowProvider.lastInvite` is set), the persistent
/// [InlineError], and the [InviteResult] card shown only after the first
/// successful create. Caller wraps this in [OnboardStepFrame] (full-screen
/// route, e.g. ChatCreateScreen) or OnboardStepBody (inline, atomic #8).
///
/// Mirrors React `ChatCreateStep` (NewSessionPanelSteps.tsx) which renders
/// its body inside an `OnboardStepFrame` -- there the frame and content
/// are coupled; here they are split so the same content composes into two
/// frames (route + inline). State stays in this widget (busy/copied/error
/// are ephemeral UI); the invite URI is server-derived via the provider.
class ChatCreateStep extends ConsumerStatefulWidget {
  const ChatCreateStep({super.key, required this.onBack});

  /// Back-navigation callback (1:1 with React `props.onBack`). The step
  /// body does not render a back affordance itself; the framing widget
  /// owns the Back button and wires it to this callback.
  final VoidCallback onBack;

  @override
  ConsumerState<ChatCreateStep> createState() => _ChatCreateStepState();
}

class _ChatCreateStepState extends ConsumerState<ChatCreateStep> {
  bool _busy = false;
  bool _copied = false;
  // Persistent inline error (parity with React's `props.error` on
  // NewSessionPanel -- stays until the next create attempt). Cleared at
  // the START of the next attempt below.
  String? _error;

  Future<void> _onCreate() async {
    if (_busy) return;
    // React resets `copied` whenever a new create begins; the previous
    // invite's "Copied" badge should not persist onto a fresh link.
    setState(() {
      _busy = true;
      _copied = false;
      _error = null;
    });
    try {
      await ref.read(inviteFlowProvider.notifier).create();
    } catch (e) {
      // Mirrors React's parent try/catch feeding `props.error` down: React
      // stores `readableError(err)` (the bare message) in state, so this
      // uses the same helper. The inline error is the ONE source of truth
      // (no SnackBar here).
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onCopy(String uri) async {
    await Clipboard.setData(ClipboardData(text: uri));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final lastInvite = ref.watch(inviteFlowProvider).lastInvite;
    final hasInvite = lastInvite != null;
    return Column(
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
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineError(message: _error),
        ],
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
    );
  }
}