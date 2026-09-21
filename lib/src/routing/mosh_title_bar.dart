// Shared desktop titlebar. Renders full-window-width ABOVE the rail+chat
// Row on desktop only; mobile screens already carry their own AppBar +
// peer-status button, so the titlebar is NOT mounted on mobile
// (documented deviation in mosh_shell.dart).
//
// Layout: brand (shield icon + strong "MOSH" product name), subtitle,
// "Peer status" button (opens the PeerStatusDrawer for the active
// conversation), then the live StatePill for the active conversation.
//
// State (all live): activeConversationKeyProvider -> key; the matching
// snapshot family is watched for the live .state (activeSessionProvider /
// channelSnapshotProvider / groupSnapshotProvider). Label mapper:
// stateLabel() (features/diagnostics/state_label.dart) -- reused, DRY.
//
// Colors: the same literals summary_card.dart / bind_interface_field.dart
// use; neutral pill chrome maps to theme.surfaceContainerHighest /
// theme.dividerColor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

// File-local pill colors, kept so the pill chrome is self-describing
// without threading a theme extension through the seed ColorScheme.
const Color _kMoss = MoshColors.moss;
const Color _kWarn = MoshColors.warn;
const Color _kFg3 = MoshColors.fg3;
// Moss-glow background: rgba(183,216,74,~0.14). summary_card.dart uses
// `Color(0x24B7D84A).withValues(alpha: 0.14)` for the ready badge; this
// file mirrors that exact recipe.
final Color _kMossGlow = const Color(0x24B7D84A).withValues(alpha: 0.14);

/// Desktop titlebar. Watches activeConversationKeyProvider + the matching
/// snapshot family only for the StatePill slot. The shell-level
/// PeerStatusDrawer toggle lives in MoshShell: this titlebar fires the
/// shell-supplied [onOpenPeerStatus] VoidCallback when the Peer status
/// button is tapped. Keeping the toggle in the shell is what rebuilds the
/// Stack so the Positioned.fill drawer actually appears (a titlebar-owned
/// toggle would no-op the shell, since the shell does not watch it).
class MoshTitleBar extends ConsumerWidget {
  const MoshTitleBar({super.key, required this.onOpenPeerStatus});

  /// Invoked when the "Peer status" button is tapped -- the shell flips
  /// its `_showPeerStatus` and rebuilds to mount the Positioned.fill
  /// PeerStatusDrawer over the whole shell. Owned by the shell, not this
  /// titlebar, so the shell rebuilds when it flips (a titlebar-owned
  /// toggle would no-op).
  final VoidCallback onOpenPeerStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final activeKey = ref.watch(activeConversationProvider);
    // 44-tall bar with a bottom hairline. Wrapped in a transparent
    // Material so the Peer status button's InkWell has an ink ancestor --
    // the shell mounts the titlebar ABOVE the branch Scaffolds, so there
    // is no Material above it.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            bottom: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Row(
          children: <Widget>[
            // Brand: shield icon + strong MOSH in moss color.
            Icon(Icons.verified_user, size: 18, color: _kMoss),
            const SizedBox(width: 8),
            Text(
              l.shellProductName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.04,
                color: theme.colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 14),
            // Subtitle: flexed out, muted, 12px, ellipsized.
            Expanded(
              child: Text(
                l.shellWindowSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // "Peer status" ghost button; fires the shell-supplied
            // onOpenPeerStatus -- the shell owns + mounts the drawer
            // overlay.
            _PeerStatusButton(onTap: onOpenPeerStatus),
            const SizedBox(width: 14),
            _StatePillSlot(activeKey: activeKey),
          ],
        ),
      ),
    );
  }
}

/// The "Peer status" ghost button (plug icon 14 + text). Icons.
/// electrical_services is the same icon the DM/Channel/Group AppBars use
/// for their peer-status action, kept for visual consistency.
class _PeerStatusButton extends StatelessWidget {
  const _PeerStatusButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: l.openPeerStatus,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.electrical_services,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  l.peerStatusTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
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

/// StatePill: inline-flex row, gap 8, height 26, horizontal padding 12,
/// radius 999, font 11.5 semibold, raised-surface bg, 1px hairline
/// border, a 7x7 round dot. Variants:
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
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: variant.background ?? theme.colorScheme.surfaceContainerHighest,
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
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.02,
              color: variant.textColor ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
        background: _kMossGlow,
        textColor: _kMoss,
        dotColor: _kMoss,
        dotGlow: <BoxShadow>[
          BoxShadow(color: _kMoss.withValues(alpha: 0.6), blurRadius: 4),
        ],
        borderColorOverride: _kMoss.withValues(alpha: 0.25),
      );
    case 'waiting':
      // waiting: warn text, warn dot, warn-tinted border; base bg.
      return _PillVariant(
        textColor: _kWarn,
        dotColor: _kWarn,
        borderColorOverride: _kWarn.withValues(alpha: 0.25),
      );
    case 'idle':
    default:
      // idle (and unknown states): default text, fg-3 dot.
      return _PillVariant(dotColor: _kFg3);
  }
}
