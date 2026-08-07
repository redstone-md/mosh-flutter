// Embeddable channel-join step body -- 1:1 with React `ChannelJoinStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx): body, the
// `.step-channel-input` box (`#` prefix + borderless TextField), Join
// button, InlineError. NO frame, NO back affordance, NO title -- the
// caller wraps this in [OnboardStepFrame] (full screen) or OnboardStepBody
// (inline, atomic #8).
//
// Scope: the step UI + the joinChannel Gateway seam (slice-3). Join calls
// `gateway.joinChannel` with the entered name + the
// displayName/listenPort/staticPeer from [inviteFlowProvider] (ADR 0010
// DRY: one settings source for both flows), then navigates to the channel
// screen on success. The name is ephemeral to this step visit (React
// per-step `useState`), so the controller stays widget-local.
//
// Navigation split (differs from atomic #4/#5): the SUCCESS navigation
// (`context.go(AppRoutes.channelFor(name))`) stays INSIDE this step -- the
// same destination for the full-screen route and the inline desktop panel.
// Only `onBack` is injected (1:1 with React `props.onBack`): the caller
// decides where Back goes (route screen -> AppRoutes.onboarding, inline
// panel -> back to menu). Hence go_router + app_router stay imported here
// for the success hop.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/inline_error.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart'
    show channelListProvider;
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;
import 'package:mosh/src/util/format.dart' show readableError;

/// Embeddable channel-join step body -- the step CONTENT only: body
/// paragraph, `.step-channel-input` box (`#` + borderless TextField), Join
/// button, persistent [InlineError]. Caller wraps this in
/// [OnboardStepFrame] (full-screen route, e.g. ChannelJoinScreen) or
/// OnboardStepBody (inline, atomic #8). Mirrors React `ChannelJoinStep`
/// (NewSessionPanelSteps.tsx). State stays in this widget
/// (name/canJoin/busy/error are ephemeral UI).
///
/// [onBack] is an injected VoidCallback (1:1 with React `props.onBack`)
/// reserved for caller parity -- the step body renders no back affordance
/// itself; the framing widget owns the Back button and wires it to this
/// callback. Unlike atomic #4/#5, this step KEEPS the success navigation
/// (`context.go(AppRoutes.channelFor(name))`) inside itself because both the
/// route screen and the inline panel land on the same channel destination.
/// Only Back routing is delegated to the caller.
class ChannelJoinStep extends ConsumerStatefulWidget {
  const ChannelJoinStep({super.key, required this.onBack});

  /// Back-navigation callback (1:1 with React `props.onBack`). The step
  /// body does not render a back affordance itself; the framing widget
  /// owns the Back button and wires it to this callback.
  final VoidCallback onBack;

  @override
  ConsumerState<ChannelJoinStep> createState() => _ChannelJoinStepState();
}

class _ChannelJoinStepState extends ConsumerState<ChannelJoinStep> {
  late final TextEditingController _nameController;
  bool _canJoin = false;
  bool _busy = false;
  // Persistent inline error (parity with React's `props.error` on
  // NewSessionPanel -- stays until the next join attempt). Cleared at
  // the START of the next join below.
  String? _error;

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

  // Calls gateway.joinChannel with a JoinChannelRequest built from the
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
      await ref
          .read(gatewayProvider)
          .joinChannel(
            request: JoinChannelRequest(
              name: name,
              displayName: settings.displayName,
              listenPort: settings.listenPort,
              staticPeer: settings.staticPeer,
            ),
          );
      await ref.read(channelListProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.channelFor(name));
    } catch (e) {
      // Mirrors React's parent try/catch feeding `props.error` down: React
      // stores `readableError(err)` (the bare message) in state, so this
      // uses the same helper. No transient SnackBar -- the inline error
      // is the one source of truth AND is announced to assistive tech via
      // the live region.
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
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
          InlineError(message: _error),
        ],
      ],
    );
  }
}
