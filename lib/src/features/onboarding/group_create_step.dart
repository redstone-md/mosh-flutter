// Embeddable group-create step body -- 1:1 with React `GroupCreateStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx): body, OPTIONAL label
// input, Create/Recreate button (label flips once an invite exists),
// InlineError, InviteResult. NO frame, NO back affordance, NO title -- the
// caller wraps this in [OnboardStepFrame] (full screen) or OnboardStepBody
// (inline, atomic #8).
//
// State split (ADR 0010): the group label + GroupCreated result are
// per-step widget-local (React keeps the label as per-step `value` and
// `groupCreateState` in `usePrivateDmSetup`, NOT in the DM
// inviteFlowProvider). Only `_busy`/`_copied`/`_error` are also ephemeral
// UI. The displayName/listenPort/staticPeer come from [inviteFlowProvider]
// -- the same settings source createInvite uses.
//
// `onBack` is injected (1:1 with React `props.onBack`): the step renders no
// back affordance itself; the framing widget owns the Back button. The step
// does NOT context.go itself; the caller decides routing (route for
// GroupCreateScreen, inline step-switch for the chat-pane in atomic #8).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;
import 'package:mosh/src/features/shared/conversation_action_error.dart';

/// Embeddable group-create step body -- the step CONTENT only: body,
/// OPTIONAL label TextField, Create/Recreate button (label flips once
/// `_created` is set), persistent [InlineError], and [InviteResult] card
/// shown after the first successful create. Caller wraps this in
/// [OnboardStepFrame] (full-screen route, e.g. GroupCreateScreen) or
/// OnboardStepBody (inline, atomic #8). Mirrors React `GroupCreateStep`
/// (NewSessionPanelSteps.tsx). State stays in this widget (label,
/// GroupCreated, busy/copied/error are ephemeral UI); the
/// displayName/listenPort/staticPeer settings come from
/// [inviteFlowProvider].
class GroupCreateStep extends ConsumerStatefulWidget {
  const GroupCreateStep({super.key, required this.onBack});

  /// Back-navigation callback (1:1 with React `props.onBack`). The step
  /// body does not render a back affordance itself; the framing widget
  /// owns the Back button and wires it to this callback.
  final VoidCallback onBack;

  @override
  ConsumerState<GroupCreateStep> createState() => _GroupCreateStepState();
}

class _GroupCreateStepState extends ConsumerState<GroupCreateStep> {
  late final TextEditingController _labelController;
  bool _busy = false;
  bool _copied = false;
  // Persistent inline error (parity with React's `props.error` on
  // NewSessionPanel -- stays until the next create attempt). Cleared at
  // the START of the next create below.
  ConversationActionError? _error;
  // The GroupCreated from the last successful create (null until the first
  // create). Kept widget-local -- React's `groupCreateState` lives in
  // `usePrivateDmSetup` per-step state, not the DM inviteFlowProvider, so
  // this mirrors that separation (ADR 0010 widget-local state for per-step
  // UI state).
  GroupCreated? _created;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  // Calls bridge.createGroup with a CreateGroupRequest built from the
  // entered label (trimmed, null if empty -- React `label.trim() || null`)
  // + inviteFlowProvider's displayName/listenPort/staticPeer (the same
  // settings source createInvite uses, ADR 0010), copies the returned invite
  // URI to the clipboard (React `copyText(created.invite_uri)`), and stores
  // the GroupCreated so the InviteResult branch renders. Stays on this step
  // (React `setShowSetup(true)` -- the user shares the invite before
  // navigating away). Mirrors ChatCreateStep's busy + reset-copied +
  // try/finally pattern.
  Future<void> _onCreate() async {
    if (_busy) return;
    final label = _labelController.text.trim();
    final settings = ref.read(inviteFlowProvider);
    setState(() {
      _busy = true;
      _copied = false;
      _error = null;
    });
    try {
      final created = await ref.read(bridgeFacadeProvider).createGroup(
            request: CreateGroupRequest(
              label: label.isEmpty ? null : label,
              displayName: settings.displayName,
              listenPort: settings.listenPort,
              staticPeer: settings.staticPeer,
            ),
          );
      await ref
          .read(conversationListProvider(ConversationKind.group).notifier)
          .refresh();
      await Clipboard.setData(ClipboardData(text: created.inviteUri));
      if (!mounted) return;
      setState(() {
        _created = created;
        _copied = true;
      });
    } catch (e) {
      // The inline error is the one source of truth (no SnackBar), and its
      // wording comes from the bridge kind when the seam threw one.
      if (mounted) setState(() => _error = ConversationActionError.of(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Re-copies the stored invite URI and flips the "Copied" badge (mirrors
  // ChatCreateStep._onCopy). Only reachable when `_created != null`.
  Future<void> _onCopy() async {
    final created = _created;
    if (created == null) return;
    await Clipboard.setData(ClipboardData(text: created.inviteUri));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // .step-body: 12.5px, 1.6 line-height, fg-3 (onSurfaceVariant).
        Text(
          l.onboardGroupStepBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12.5,
            height: 1.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        // .step-input: rounded bordered TextField, 12.5px text. The
        // label is OPTIONAL in React (Create is `disabled={busy}` only),
        // so the input stays enabled regardless of whether text exists.
        TextField(
          controller: _labelController,
          decoration: InputDecoration(
            hintText: l.onboardGroupNamePlaceholder,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          style: const TextStyle(fontSize: 12.5),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onCreate(),
        ),
        const SizedBox(height: 20),
        // .btn.btn-primary.btn-block: full-width primary (mirrors
        // ChatCreateStep's FilledButton with minimumSize 48h). The label
        // flips Create/Recreate based on `_created` (null = first create).
        // NOT disabled by an empty label (React `disabled={busy}` only).
        FilledButton(
          onPressed: _busy ? null : _onCreate,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _created != null
                      ? l.onboardGroupRecreate
                      : l.onboardGroupCreate,
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineError(message: _error?.describe(l)),
        ],
        // Renders only after a successful create (`_created != null`).
        // Mirrors React's GroupCreateStep InviteResult card; the URI is
        // auto-copied on create and re-copyable via `_onCopy`.
        if (_created != null) ...[
          const SizedBox(height: 20),
          InviteResult(
            note: l.onboardGroupInviteReady,
            uri: _created!.inviteUri,
            copied: _copied,
            onCopy: _onCopy,
          ),
        ],
      ],
    );
  }
}
