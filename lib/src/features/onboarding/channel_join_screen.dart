// Channel-join step, 1-в-1 with the React `ChannelJoinStep`
// (src/features/private-dm/NewSessionPanelSteps.tsx). Mirrors the React
// flow: a step frame (OnboardStepFrame) with the channel title, a body
// paragraph, the `.step-channel-input` box (`#` prefix + borderless
// TextField), and the Join button.
//
// Scope (this atomic): the channel-join step UI ONLY. The Gateway
// `joinChannel` seam is a LATER slice (Rust `join_channel_room` exists;
// the Flutter Gateway method is deferred), so the Join button is a
// NO-OP STUB that shows a "later slice" SnackBar -- mirroring how the
// channel tile previously used `_showLaterSlice`. The name is ephemeral
// to this screen visit (React keeps it as per-step `useState`), so the
// TextEditingController stays widget-local and is not lifted to a store.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

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

  // NO-OP STUB: the Gateway `joinChannel` seam is a later slice. Mirror the
  // channel tile's former `_showLaterSlice` behavior so the button is honest
  // about what is and isn't wired yet.
  void _onJoin() {
    if (!_canJoin) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.onboardJoinStepBody)),
    );
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
            onPressed: _canJoin ? _onJoin : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(l.onboardChannelJoin),
          ),
        ],
      ),
    );
  }
}
