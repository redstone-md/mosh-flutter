// Channel-join step, 1-в-1 with the React `ChannelJoinStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx). Mirrors the React
// flow: a step frame (OnboardStepFrame) with the channel title, a body
// paragraph, the `.step-channel-input` box (`#` prefix + borderless
// TextField), and the Join button.
//
// Scope: the channel-join step UI + the joinChannel Gateway seam (slice-3).
// Tapping Join calls `gateway.joinChannel` with a JoinChannelRequest built
// from the entered name + the displayName/listenPort/staticPeer that
// [inviteFlowProvider] already sources for createInvite (ADR 0010 DRY: one
// settings source for both flows), then navigates to the channel screen on
// success. The name is ephemeral to this screen visit (React keeps it as
// per-step `useState`), so the TextEditingController stays widget-local and
// is not lifted to a store.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;

/// The channel-join step screen.
///
/// Reached from the onboarding Channel tile (`context.go(AppRoutes.channelJoin)`).
/// Tapping Join is a NO-OP STUB that shows a "later slice" SnackBar (the
/// Gateway `joinChannel` seam is deferred). Back returns to the onboarding
/// menu (`AppRoutes.onboarding`). The entered channel name is ephemeral to
/// this visit, mirroring React's per-step `value` state.
class ChannelJoinScreen extends ConsumerStatefulWidget {
  const ChannelJoinScreen({super.key});

  @override
  ConsumerState<ChannelJoinScreen> createState() => _ChannelJoinScreenState();
}

class _ChannelJoinScreenState extends ConsumerState<ChannelJoinScreen> {
  late final TextEditingController _nameController;
  bool _canJoin = false;
  bool _busy = false;

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

  void _onBack() => context.go(AppRoutes.onboarding);

  // Calls gateway.joinChannel with a JoinChannelRequest built from the
  // entered name + inviteFlowProvider's displayName/listenPort/staticPeer
  // (the same settings source createInvite uses), then navigates to the
  // channel screen on success. Mirrors channel_screen's _send/_leave busy +
  // try/finally pattern.
  Future<void> _onJoin() async {
    if (!_canJoin || _busy) return;
    final name = _nameController.text.trim();
    final settings = ref.read(inviteFlowProvider);
    setState(() => _busy = true);
    try {
      await ref.read(gatewayProvider).joinChannel(
            request: JoinChannelRequest(
              name: name,
              displayName: settings.displayName,
              listenPort: settings.listenPort,
              staticPeer: settings.staticPeer,
            ),
          );
      if (!mounted) return;
      context.go(AppRoutes.channelFor(name));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return OnboardStepFrame(
      title: l.onboardTileChannelTitle,
      onBack: _onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .step-body: 12.5px, 1.6 line-height, fg-3 (onSurfaceVariant).
          Text(
            l.onboardChannelStepBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
              height: 1.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // .step-channel-input: rounded bordered box with `#` + borderless
          // input. The `#` is aria-hidden in React (decorative).
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor),
              color: theme.colorScheme.surfaceContainerLowest,
            ),
            child: Row(
              children: [
                Text(
                  '#',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: l.onboardChannelPlaceholder,
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
                    ),
                    style: const TextStyle(fontSize: 12.5),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _onJoin(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // .btn.btn-primary.btn-block: full-width primary (mirrors
          // ChatCreateScreen's FilledButton with minimumSize 48h).
          FilledButton(
            onPressed: (_canJoin && !_busy) ? _onJoin : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.onboardChannelJoin),
          ),
        ],
      ),
    );
  }
}
