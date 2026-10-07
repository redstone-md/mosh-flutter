import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

class GroupCreateStep extends ConsumerStatefulWidget {
  const GroupCreateStep({super.key});

  @override
  ConsumerState<GroupCreateStep> createState() => _GroupCreateStepState();
}

class _GroupCreateStepState extends ConsumerState<GroupCreateStep> {
  late final TextEditingController _labelController;
  bool _busy = false;
  bool _copied = false;
  // Persistent inline error -- stays until the next create attempt.
  // Cleared at the START of the next create below.
  ConversationActionError? _error;
  // The GroupCreated from the last successful create (null until the first
  // create). Kept widget-local -- per-step UI state stays out of the DM
  // inviteFlowProvider (ADR 0010).
  GroupCreated? _created;

  bool _named = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: '')
      ..addListener(() {
        final named = _labelController.text.trim().isNotEmpty;
        if (named != _named) setState(() => _named = named);
      });
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  // Calls bridge.createGroup with a CreateGroupRequest built from the
  // entered name (trimmed; the form requires one) + inviteFlowProvider's
  // displayName/listenPort/staticPeer (the same settings source
  // createInvite uses, ADR 0010), copies the returned invite URI to the
  // clipboard, and stores the GroupCreated so the InviteResult branch
  // renders. Stays on this step -- the user shares the invite before
  // navigating away; the card's Open button is the way in. Mirrors
  // ChatCreateStep's busy + reset-copied + try/finally pattern.
  Future<void> _onCreate() async {
    if (_busy || !_named) return;
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
              label: label,
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
    final toaster = context.toaster;
    final copied = AppLocalizations.of(context)!.messageCopied;
    await Clipboard.setData(ClipboardData(text: created.inviteUri));
    toaster.show(copied, kind: ToastKind.success);
    if (mounted) setState(() => _copied = true);
  }

  /// Back to an empty form for another group.
  void _onAnother() => setState(() {
        _created = null;
        _copied = false;
        _labelController.clear();
      });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final created = _created;
    if (created != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InviteResult(
            note: l.onboardGroupInviteReady,
            uri: created.inviteUri,
            copied: _copied,
            onCopy: _onCopy,
            openLabel: l.onboardOpenGroup,
            onOpen: () => context.go(AppRoutes.groupFor(created.groupId)),
            footer: l.onboardGroupInviteFooter,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _onAnother, child: Text(l.onboardGroupAnother)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _labelController,
          decoration: InputDecoration(
            labelText: l.onboardGroupNameLabel,
            helperText: l.onboardGroupNameHint,
            prefixIcon: const Icon(Icons.group_outlined, size: 20),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onCreate(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || !_named ? null : _onCreate,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.onboardGroupCreate),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineError(message: _error?.describe(l)),
        ],
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 18, color: MoshColors.fg3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.onboardGroupMembersNote,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: MoshColors.fg3, height: 1.45)),
          ),
        ]),
      ],
    );
  }
}
