import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;
import 'package:mosh/src/features/shared/conversation_action_error.dart';

class ChannelJoinStep extends ConsumerStatefulWidget {
  const ChannelJoinStep({super.key});

  @override
  ConsumerState<ChannelJoinStep> createState() => _ChannelJoinStepState();
}

class _ChannelJoinStepState extends ConsumerState<ChannelJoinStep> {
  late final TextEditingController _nameController;
  bool _canJoin = false;
  bool _busy = false;
  // Persistent inline error -- stays until the next join attempt.
  // Cleared at the START of the next join below.
  ConversationActionError? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '');
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    final canJoin = _nameController.text.trim().isNotEmpty;
    if (canJoin != _canJoin) setState(() => _canJoin = canJoin);
  }

  // Calls bridge.joinChannel with a JoinChannelRequest built from the
  // entered name + inviteFlowProvider's displayName/listenPort/staticPeer
  // (the same settings source createInvite uses), then navigates to the
  // channel screen on success. Mirrors channel_screen's _send/_leave busy +
  // try/finally pattern.
  Future<void> _onJoin() async {
    if (!_canJoin || _busy) return;
    final name = _nameController.text.trim();
    final settings = ref.read(inviteFlowProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final joined = await ref.read(bridgeFacadeProvider).joinChannel(
            request: JoinChannelRequest(
              name: name,
              displayName: settings.displayName,
              listenPort: settings.listenPort,
              staticPeer: settings.staticPeer,
            ),
          );
      await ref
          .read(conversationListProvider(ConversationKind.channel).notifier)
          .refresh();
      if (!mounted) return;
      // The core normalizes the name (`#News` joins `news`).
      context.go(AppRoutes.channelFor(joined.name));
    } catch (e) {
      // The inline error is the one source of truth (no SnackBar), and its
      // wording comes from the bridge kind when the seam threw one.
      if (mounted) setState(() => _error = ConversationActionError.of(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OpenWarning(text: l.onboardChannelStepBody),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: l.onboardChannelNameLabel,
            hintText: l.onboardChannelPlaceholder,
            helperText: l.onboardChannelNameRule,
            prefixIcon: const Icon(Icons.tag, size: 20),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onJoin(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: (_canJoin && !_busy) ? _onJoin : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.onboardChannelJoin),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineError(message: _error?.describe(l)),
        ],
        const SizedBox(height: 24),
        _Examples(
          label: l.onboardChannelExamples,
          onPick: (name) => _nameController.value = TextEditingValue(
            text: name,
            selection: TextSelection.collapsed(offset: name.length),
          ),
        ),
      ],
    );
  }
}

/// Public channels are plaintext; say so before anyone types.
class _OpenWarning extends StatelessWidget {
  const _OpenWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MoshColors.warnSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MoshColors.warnBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lock_open, size: 20, color: MoshColors.warn),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: MoshColors.fg1, height: 1.5)),
        ),
      ]),
    );
  }
}

/// Names that pass the core's rule, one tap to fill in.
class _Examples extends StatelessWidget {
  const _Examples({required this.label, required this.onPick});

  final String label;
  final ValueChanged<String> onPick;

  static const names = ['news', 'dev', 'community'];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: MoshColors.fg3);
    return Column(children: [
      Row(children: [
        const Expanded(child: Divider(color: MoshColors.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: style),
        ),
        const Expanded(child: Divider(color: MoshColors.line)),
      ]),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final name in names)
            ActionChip(
              avatar: const Icon(Icons.tag, size: 16, color: MoshColors.fg3),
              label: Text(name),
              onPressed: () => onPick(name),
            ),
        ],
      ),
    ]);
  }
}
