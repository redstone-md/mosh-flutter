import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/platform/desktop_chrome_scope.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Below this width at normal text scale, Peer status shows only its icon.
const double _kCompactWidth = 640;

/// Widest the live state pill grows before its label ellipsizes.
const double _kStatePillMaxWidth = 240;

/// Shared application branding and selected-conversation diagnostics.
class MoshTitleBar extends ConsumerWidget {
  const MoshTitleBar(
      {super.key,
      required this.onOpenPeerStatus,
      this.showChatList = true,
      this.onToggleChatList,
      this.integrated = false,
      this.leading = const SizedBox.shrink(),
      this.trailing = const SizedBox.shrink(),
      this.dragArea});

  const MoshTitleBar.brand({super.key})
      : onOpenPeerStatus = null,
        showChatList = false,
        onToggleChatList = null,
        integrated = false,
        leading = const SizedBox.shrink(),
        trailing = const SizedBox.shrink(),
        dragArea = null;

  final VoidCallback? onOpenPeerStatus;
  final bool showChatList;
  final VoidCallback? onToggleChatList;
  final bool integrated;
  final Widget leading;
  final Widget trailing;
  final Widget Function(Widget child)? dragArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!integrated && DesktopChromeScope.isPresent(context)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final active =
        onOpenPeerStatus == null ? null : ref.watch(activeConversationProvider);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            return Row(children: [
              leading,
              const SizedBox(width: 8),
              if (showChatList) _ChatListToggle(onPressed: onToggleChatList),
              Expanded(
                  child: _branding(context,
                      showName: constraints.maxWidth >= 480 * scale)),
              if (active != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: _kStatePillMaxWidth),
                      child: _StatePillSlot(
                          activeKey: active,
                          compact:
                              constraints.maxWidth < _kCompactWidth * scale,
                          onTap: onOpenPeerStatus!),
                    )),
              trailing,
              if (!integrated) const SizedBox(width: 8),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _branding(BuildContext context, {required bool showName}) {
    final brand = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        Image.asset('assets/branding/mosh-mark.png',
            width: 18, height: 18, excludeFromSemantics: true),
        if (showName) ...[
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.shellProductName,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.56)),
        ],
      ]),
    );
    return dragArea?.call(brand) ?? brand;
  }
}

/// Collapses the chat list to its avatar strip and expands it back.
class _ChatListToggle extends ConsumerWidget {
  const _ChatListToggle({this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final collapsed = ref.watch(railLayoutProvider.select((l) => l.collapsed));
    return IconButton(
      tooltip: onPressed != null || collapsed
          ? l.chatListExpand
          : l.chatListCollapse,
      icon: Icon(onPressed != null || collapsed ? Icons.menu : Icons.menu_open,
          size: 18),
      style: _focusRingStyle,
      visualDensity: VisualDensity.compact,
      onPressed:
          onPressed ?? () => ref.read(railLayoutProvider.notifier).toggle(),
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

/// Uses existing conversation state mapping; never claims global connectivity.
class _StatePillSlot extends ConsumerWidget {
  const _StatePillSlot(
      {required this.activeKey, required this.compact, required this.onTap});
  final ActiveConversation activeKey;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final (state, label) = switch (activeKey.kind) {
      ConversationKind.dm => _dm(ref, l),
      ConversationKind.channel => ('idle', l.channelBroadcastBadge),
      ConversationKind.group => _group(ref, l),
    };
    return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        child: Tooltip(
          message: l.peerStatusTitle,
          child: Semantics(
              label: l.peerStatusTitle,
              value: label,
              button: true,
              onTap: onTap,
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTap,
                child: FocusRing(
                    radius: BorderRadius.circular(999),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: StatePill(
                            state: state, label: label, compact: compact))),
              )),
        ));
  }

  (String, String) _dm(WidgetRef ref, AppLocalizations l) {
    final snapshot = ref.watch(activeSessionProvider(activeKey.arg));
    final state = snapshot.hasError ? null : snapshot.value?.state;
    return state == null
        ? ('unknown', l.diagPeerUnknown)
        : (dmPillState(state), dmStateLabel(l, state));
  }

  (String, String) _group(WidgetRef ref, AppLocalizations l) {
    final snapshot = ref.watch(groupSnapshotProvider(activeKey.arg));
    final state = snapshot.hasError ? null : snapshot.value?.state;
    return state == null
        ? ('unknown', l.diagPeerUnknown)
        : (state, stateLabel(l, state));
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
  const StatePill(
      {super.key,
      required this.state,
      required this.label,
      this.compact = false});

  /// The raw state string ('idle' / 'waiting' / 'ready' / ...).
  final String state;

  /// The localized label (stateLabel output for dm/group; the broadcast
  /// badge text for channels).
  final String label;
  final bool compact;

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
            if (!compact) const SizedBox(width: 8),
            if (!compact)
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
