import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/app/mosh_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/inline_error.dart';
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
  // navigating away; the card's Open button is the way in. Busy covers the
  // creation only, so leaving the result never waits on the clipboard.
  Future<void> _onCreate() async {
    if (_busy || !_named) return;
    final label = _labelController.text.trim();
    final settings = ref.read(inviteFlowProvider);
    setState(() {
      _busy = true;
      _copied = false;
      _error = null;
    });
    final GroupCreated created;
    try {
      created = await ref.read(bridgeFacadeProvider).createGroup(
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
    } catch (e) {
      // The inline error is the one source of truth (no SnackBar), and its
      // wording comes from the bridge kind when the seam threw one.
      if (mounted) setState(() => _error = ConversationActionError.of(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    setState(() => _created = created);
    await _copyCreated(created);
  }

  // The group exists now: a busy clipboard only leaves it uncopied, and the
  // result's Copy button is still there. Marks it copied only while that
  // result is still the one showing.
  Future<void> _copyCreated(GroupCreated created) async {
    try {
      await Clipboard.setData(ClipboardData(text: created.inviteUri));
    } on PlatformException {
      return;
    }
    if (mounted && identical(_created, created)) {
      setState(() => _copied = true);
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
    final colors = MoshColors.of(context);
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
        MoshField(
          label: l.onboardGroupNameLabel,
          child: TextField(
            controller: _labelController,
            decoration: InputDecoration(
              helperText: l.onboardGroupNameHint,
              prefixIcon: const Icon(MoshIcons.group, size: 20),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _onCreate(),
          ),
        ),
        const SizedBox(height: 20),
        MoshLoading(
          loading: _busy,
          child: FilledButton.icon(
            onPressed: _named ? _onCreate : null,
            icon: _busy ? const MoshSpinner() : null,
            label: Text(l.onboardGroupCreate),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineError(message: _error?.describe(l)),
        ],
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(MoshIcons.info, size: 18, color: colors.onSurfaceMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.onboardGroupMembersNote,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceMuted, height: 1.45)),
          ),
        ]),
      ],
    );
  }
}
