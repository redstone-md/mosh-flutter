import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Below this width at normal text scale, Peer status shows only its icon.
const double _kCompactWidth = 640;

const IconData _kPeerStatusIcon = Icons.electrical_services_outlined;

/// Desktop titlebar. Watches activeConversationKeyProvider + the matching
/// snapshot family only for the StatePill slot. The shell-level
/// PeerStatusDrawer toggle lives in MoshShell: this titlebar fires the
/// shell-supplied [onOpenPeerStatus] VoidCallback when the Peer status
/// button is tapped. Keeping the toggle in the shell is what rebuilds the
/// Stack so the Positioned.fill drawer actually appears (a titlebar-owned
/// toggle would no-op the shell, since the shell does not watch it).
class MoshTitleBar extends ConsumerWidget {
  const MoshTitleBar({super.key, required this.onOpenPeerStatus});

  /// Settings retain window branding without the hidden chat's live status.
  const MoshTitleBar.brand({super.key}) : onOpenPeerStatus = null;

  /// Invoked when the "Peer status" button is tapped -- the shell flips
  /// its `_showPeerStatus` and rebuilds to mount the Positioned.fill
  /// PeerStatusDrawer over the whole shell. Owned by the shell, not this
  /// titlebar, so the shell rebuilds when it flips (a titlebar-owned
  /// toggle would no-op).
  final VoidCallback? onOpenPeerStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeKey =
        onOpenPeerStatus == null ? null : ref.watch(activeConversationProvider);
    // The Material carries the bar fill, so the Peer status button's ink
    // paints above it. The shell mounts the titlebar ABOVE the branch
    // Scaffolds, so there is no other Material to draw on.
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => _row(
            context,
            activeKey,
            compact: constraints.maxWidth <
                _kCompactWidth *
                    MediaQuery.textScalerOf(context).scale(14) /
                    14,
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ActiveConversation? activeKey,
      {required bool compact}) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Image.asset('assets/branding/mosh-mark.png',
            width: 18, height: 18, excludeFromSemantics: true),
        const SizedBox(width: 8),
        Text(
          l.shellProductName,
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.04 * 14,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Tooltip(
            message: l.shellWindowSubtitle,
            excludeFromSemantics: true,
            child: Text(
              l.shellWindowSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ),
        ),
        if (onOpenPeerStatus != null) ...[
          const SizedBox(width: 14),
          Flexible(
              child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    compact
                        ? IconButton(
                            tooltip: l.peerStatusTitle,
                            icon: const Icon(_kPeerStatusIcon, size: 18),
                            style: _focusRingStyle,
                            onPressed: onOpenPeerStatus,
                          )
                        : _PeerStatusButton(onTap: onOpenPeerStatus!),
                    const SizedBox(width: 14),
                    Flexible(child: _StatePillSlot(activeKey: activeKey)),
                  ]))),
        ],
      ],
    );
  }
}

/// The [FocusRing] border for a stock button: `focused` is only set while
/// the keyboard focus highlight shows.
final ButtonStyle _focusRingStyle = ButtonStyle(
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: MoshColors.focusRing, width: 2)
        : null,
  ),
);

/// The "Peer status" ghost button (plug icon 14 + text), the same icon the
/// DM/Channel/Group AppBars use for their peer-status action. The visible
/// text is its accessible name; the InkWell supplies button semantics.
class _PeerStatusButton extends StatelessWidget {
  const _PeerStatusButton({required this.onTap});

  final VoidCallback onTap;

  static final BorderRadius _radius = BorderRadius.circular(6);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: _radius,
      onTap: onTap,
      child: FocusRing(
        radius: _radius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _kPeerStatusIcon,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(l.peerStatusTitle, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The StatePill slot. Renders the live pill for the active conversation
/// kind, or nothing when no conversation is open. Watches the matching
/// snapshot family for the live `.state` (dm/group); the channel branch
/// renders a fixed ready pill + channelBroadcastBadge text regardless of
/// state (ChannelSnapshot has no .state field).
class _StatePillSlot extends ConsumerWidget {
  const _StatePillSlot({required this.activeKey});

  final ActiveConversation? activeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeKey = this.activeKey;
    if (activeKey == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    switch (activeKey.kind) {
      case ConversationKind.dm:
        final async = ref.watch(activeSessionProvider(activeKey.arg));
        final state = async.value?.state;
        if (state == null) return const SizedBox.shrink();
        return StatePill(
            state: dmPillState(state), label: dmStateLabel(l, state));
      case ConversationKind.channel:
        // Channels are always in the Broadcast state; ChannelSnapshot has
        // no .state.
        return StatePill(state: 'ready', label: l.channelBroadcastBadge);
      case ConversationKind.group:
        final async = ref.watch(groupSnapshotProvider(activeKey.arg));
        final state = async.value?.state;
        if (state == null) return const SizedBox.shrink();
        return StatePill(state: state, label: stateLabel(l, state));
    }
  }
}

/// StatePill: inline-flex row, gap 8, min height 26 (grows with the text),
/// padding 12x3, radius 999, labelMedium ellipsized (full label in a
/// tooltip), raised-surface bg, 1px hairline border, a 7x7 round dot.
/// Variants:
///   ready   = moss-glow bg + moss text + moss dot with glow
///   waiting = warn text + warn dot (default bg)
///   idle    = default text + fg-3 dot
/// Unknown states fall back to the idle chrome.
class StatePill extends StatelessWidget {
  const StatePill({super.key, required this.state, required this.label});

  /// The raw state string ('idle' / 'waiting' / 'ready' / ...).
  final String state;

  /// The localized label (stateLabel output for dm/group; the broadcast
  /// badge text for channels).
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variant = _pillVariant(state);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color:
              variant.background ?? theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: variant.border(theme)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 7x7 round state dot; ready gets a moss glow shadow.
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: variant.dotColor,
                shape: BoxShape.circle,
                boxShadow: variant.dotGlow,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.02 * 11.5,
                  color: variant.textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The resolved pill visual variant for a given state. null fields fall
/// back to the neutral pill chrome in [StatePill.build].
class _PillVariant {
  const _PillVariant({
    this.background,
    this.textColor,
    this.dotColor,
    this.dotGlow,
    this.borderColorOverride,
  });

  /// The pill background; null = base bg-2 (surfaceContainerHighest).
  final Color? background;

  /// The label text color; null = base fg-2 (onSurfaceVariant).
  final Color? textColor;

  /// The dot color; null = base fg-3 (onSurfaceVariant).
  final Color? dotColor;

  /// The dot box-shadow list (ready gets the moss glow); null = none.
  final List<BoxShadow>? dotGlow;

  /// An explicit border color (ready/waiting tint); null = line.
  final Color? borderColorOverride;

  Color border(ThemeData theme) => borderColorOverride ?? theme.dividerColor;
}

_PillVariant _pillVariant(String state) {
  switch (state) {
    case 'ready':
      // ready: moss-glow bg, moss text, moss dot + glow, moss border.
      return _PillVariant(
        background: MoshColors.mossGlow,
        textColor: MoshColors.moss,
        dotColor: MoshColors.moss,
        dotGlow: <BoxShadow>[
          BoxShadow(
              color: MoshColors.moss.withValues(alpha: 0.6), blurRadius: 4),
        ],
        borderColorOverride: MoshColors.moss.withValues(alpha: 0.25),
      );
    case 'waiting':
      // waiting: warn text, warn dot, warn-tinted border; base bg.
      return _PillVariant(
        textColor: MoshColors.warn,
        dotColor: MoshColors.warn,
        borderColorOverride: MoshColors.warn.withValues(alpha: 0.25),
      );
    case 'idle':
    default:
      // idle (and unknown states): default text, fg-3 dot.
      return _PillVariant(dotColor: MoshColors.fg3);
  }
}
