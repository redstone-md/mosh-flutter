// Shared desktop titlebar -- the Flutter port of React's
// private-dm-screen.tsx `header.titlebar` (L252-292) + `StatePill`
// (L526-532) + desktop-shell.css titlebar/brand/subtitle/action/state-pill
// (L16-90). Renders full-window-width ABOVE the rail+chat Row on desktop
// only; mobile screens already carry their own AppBar + peer-status
// button, so the titlebar is NOT mounted on mobile (documented deviation
// in mosh_shell.dart).
//
// Mirrored 1-1 from React (private-dm-screen.tsx L252-292):
//   1. rail toggle button (IconMenu2) -- SKIPPED: Flutter's rail is a
//      fixed 300px pane with no collapse mode, so the toggle would be a
//      dead control.
//   2. brand: shield-check icon (18) + strong "MOSH" (shellProductName).
//   3. subtitle: "Private DM . OpenMLS over Moss" (shellWindowSubtitle),
//      flex-1, ellipsized, fg-3, 12px.
//   4. "Peer status" button (plug icon 14 + text, aria-label
//      openPeerStatus) -- opens the PeerStatusDrawer for the active
//      conversation.
//   5. StatePill branch (L282-292): dm -> StatePill(state, label);
//      channel -> fixed ready pill + channelBroadcastBadge (Channel
//      snapshots have no .state); group -> StatePill(state, label); no
//      active key -> no pill.
//
// State (all live): activeConversationKeyProvider -> key; the matching
// snapshot family is watched for the live .state (activeSessionProvider /
// channelSnapshotProvider / groupSnapshotProvider). Label mapper:
// stateLabel() (features/diagnostics/state_label.dart) -- reused, DRY.
//
// Colors: React's `--moss` (#B7D84A) / `--warn` (#E8B65A) / `--fg-3`
// (#6B7075) tokens are the same literals summary_card.dart /
// bind_interface_field.dart use; neutral pill chrome maps to
// theme.surfaceContainerHighest / theme.dividerColor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/session_providers.dart';

// React CSS color tokens -- the same literals summary_card.dart and
// bind_interface_field.dart already use (--moss / --warn / --fg-3). Kept
// here as file-local constants so the pill chrome is self-describing
// without threading a theme extension through the seed ColorScheme.
const Color _kMoss = Color(0xFFB7D84A); // --moss
const Color _kWarn = Color(0xFFE8B65A); // --warn
const Color _kFg3 = Color(0xFF6B7075); // --fg-3 (idle dot)
// --moss-glow background: rgba(183,216,74,~0.14). summary_card.dart uses
// `Color(0x24B7D84A).withValues(alpha: 0.14)` for the ready badge; this
// file mirrors that exact recipe.
final Color _kMossGlow = const Color(0x24B7D84A).withValues(alpha: 0.14);

/// Desktop titlebar -- React header.titlebar (private-dm-screen.tsx
/// L252-292). A stateless-ish ConsumerWidget: it watches
/// activeConversationKeyProvider + the matching snapshot family only for
/// the StatePill slot. The shell-level PeerStatusDrawer toggle lives in
/// MoshShell (mirrors dm_screen.dart L83 + L683-691 -- the SAME widget
/// owns the toggle AND mounts the overlay); this titlebar fires the
/// shell-supplied [onOpenPeerStatus] VoidCallback when the Peer status
/// button is tapped. Keeping the toggle in the shell is what rebuilds
/// the Stack so the Positioned.fill drawer actually appears (a
/// titlebar-owned toggle would no-op the shell, since the shell does
/// not watch it).
class MoshTitleBar extends ConsumerWidget {
  const MoshTitleBar({super.key, required this.onOpenPeerStatus});

  /// Invoked when the "Peer status" button is tapped -- the shell flips
  /// its `_showPeerStatus` and rebuilds to mount the Positioned.fill
  /// PeerStatusDrawer over the whole shell (mirrors dm_screen.dart
  /// L683-691). Owned by the shell, not this titlebar, so the shell
  /// rebuilds when it flips (a titlebar-owned toggle would no-op).
  final VoidCallback onOpenPeerStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final activeKey = ref.watch(activeConversationProvider);
    // React titlebar: height 44, row, gap 14, padding 0 18, bg-0, bottom
    // border line (desktop-shell.css L16-26). Mapped to a 44-tall
    // Container with a bottom BorderSide.
    // Wrapped in a transparent Material so the Peer status button's
    // InkWell has an ink ancestor -- the shell mounts the titlebar ABOVE
    // the branch Scaffolds, so there is no Material above it.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor, // --bg-0
          border: Border(
            bottom: BorderSide(color: theme.dividerColor),
          ), // --line
        ),
        child: Row(
          children: <Widget>[
            // React: brand (IconShieldCheck 18 + strong MOSH), moss color
            // (desktop-shell.css L28-37). The closest material icon to
            // tabler's shield-check is Icons.verified_user (shield+check).
            Icon(Icons.verified_user, size: 18, color: _kMoss),
            const SizedBox(width: 8),
            Text(
              l.shellProductName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.04,
                color: theme.colorScheme.onSurface, // --fg-1
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 14),
            // React: titlebar-subtitle (flex 1, fg-3, 12px, ellipsized)
            // (desktop-shell.css L39-46).
            Expanded(
              child: Text(
                l.shellWindowSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant, // --fg-3
                ),
              ),
            ),
            const SizedBox(width: 14),
            // React: titlebar-action button (IconPlugConnected 14 + text
            // "Peer status", aria-label openPeerStatus) (private-dm-
            // screen.tsx L270-279, desktop-shell.css L48-52). Fires the
            // shell-supplied onOpenPeerStatus -- the shell owns + mounts
            // the drawer overlay (mirrors dm_screen.dart L683-691).
            _PeerStatusButton(onTap: onOpenPeerStatus),
            const SizedBox(width: 14),
            // React: StatePill branch (private-dm-screen.tsx L282-292).
            _StatePillSlot(activeKey: activeKey),
          ],
        ),
      ),
    );
  }
}

/// React: titlebar-action ghost button -- IconPlugConnected 14 + "Peer
/// status" text, aria-label openPeerStatus (private-dm-screen.tsx
/// L270-279). The closest material icon to tabler's plug-connected is
/// Icons.electrical_services (the same icon the DM/Channel/Group AppBars
/// use for their peer-status action, kept for visual consistency).
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

/// React: the StatePill branch (private-dm-screen.tsx L282-292). Renders
/// the live pill for the active conversation kind, or nothing when no
/// conversation is open. Watches the matching snapshot family for the
/// live `.state` (dm/group); the channel branch renders a fixed ready
/// pill + channelBroadcastBadge text regardless of state (React parity
/// -- ChannelSnapshot has no .state field).
class _StatePillSlot extends ConsumerWidget {
  const _StatePillSlot({required this.activeKey});

  final ActiveConversation? activeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeKey = this.activeKey;
    if (activeKey == null) return const SizedBox.shrink(); // React `: null`
    final l = AppLocalizations.of(context)!;
    switch (activeKey.kind) {
      case ConversationKind.dm:
        final async = ref.watch(activeSessionProvider(activeKey.arg));
        final state = async.value?.state;
        if (state == null) return const SizedBox.shrink();
        return StatePill(state: state, label: stateLabel(l, state));
      case ConversationKind.channel:
        // React: fixed ready pill + channelBroadcastBadge text
        // (private-dm-screen.tsx L286-290) -- channels are always in the
        // Broadcast state; ChannelSnapshot has no .state.
        return StatePill(state: 'ready', label: l.channelBroadcastBadge);
      case ConversationKind.group:
        final async = ref.watch(groupSnapshotProvider(activeKey.arg));
        final state = async.value?.state;
        if (state == null) return const SizedBox.shrink();
        return StatePill(state: state, label: stateLabel(l, state));
    }
  }
}

/// React: StatePill (private-dm-screen.tsx L526-532) + state-pill CSS
/// (desktop-shell.css L63-90). Inline-flex row, gap 8, height 26,
/// horizontal padding 12, radius 999, font 11.5 semibold, bg-2 bg, 1px
/// line border, a 7x7 round dot. Variants:
///   ready   = moss-glow bg + moss text + moss dot with glow
///   waiting = warn text + warn dot (default bg)
///   idle    = default text + fg-3 dot
/// Unknown states fall back to the idle chrome (React has no variant
/// class for unknown states, so the base `.state-pill` styles apply).
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
          // React: .state-dot (7x7 round). ready gets a moss glow shadow.
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

/// The resolved pill visual variant for a given state. Maps React's
/// `.state-pill-<state>` classes (desktop-shell.css L85-90) to Flutter
/// colors. null fields fall back to the base `.state-pill` chrome in
/// [StatePill.build].
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

  Color border(ThemeData theme) =>
      borderColorOverride ?? theme.dividerColor; // --line
}

_PillVariant _pillVariant(String state) {
  switch (state) {
    case 'ready':
      // .state-pill-ready: moss-glow bg, moss text, moss dot + glow,
      // border rgba(183,216,74,0.25).
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
      // .state-pill-waiting: warn text, warn dot, border
      // rgba(232,182,90,0.25); base bg.
      return _PillVariant(
        textColor: _kWarn,
        dotColor: _kWarn,
        borderColorOverride: _kWarn.withValues(alpha: 0.25),
      );
    case 'idle':
    default:
      // .state-pill-idle (and unknown states): default text, fg-3 dot.
      return _PillVariant(dotColor: _kFg3);
  }
}
