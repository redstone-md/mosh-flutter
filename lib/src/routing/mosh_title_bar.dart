import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/voice_call/call_plate.dart' show TitleBarCall;
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

/// How much of the bar a minimized call's plate may take.
const double _kCallPlateShare = 0.4;

/// The Window title bar card: the app's mark, the chat list toggle, a
/// minimized call and the state of the selected conversation, on the panel level so it reads as part
/// of the window's frame. The desktop window frame adds the window buttons
/// and the drag area; a phone has no title bar.
class MoshTitleBar extends ConsumerWidget {
  const MoshTitleBar(
      {super.key,
      required this.onOpenPeerStatus,
      this.showChatList = true,
      this.onToggleChatList,
      this.integrated = false,
      this.showName = true,
      this.leading = const SizedBox.shrink(),
      this.trailing,
      this.dragArea});

  const MoshTitleBar.brand({super.key, this.showName = true})
      : onOpenPeerStatus = null,
        showChatList = false,
        onToggleChatList = null,
        integrated = false,
        leading = const SizedBox.shrink(),
        trailing = null,
        dragArea = null;

  /// Whether a screen outside the chat shell draws the bar itself: the
  /// desktop's window frame has not drawn one, and the device is not a phone,
  /// which has no window and so no title bar.
  static bool standsAlone(BuildContext context) =>
      !DesktopChromeScope.isPresent(context) &&
      !MoshControl.touch(Theme.of(context).platform);

  /// The bar's height at the normal text size; it grows with larger text.
  static const double height = MoshSpace.s10;

  final VoidCallback? onOpenPeerStatus;
  final bool showChatList;
  final VoidCallback? onToggleChatList;
  final bool integrated;

  /// False during setup, whose bar is the mark alone: it has no name and,
  /// with no chats yet, no call.
  final bool showName;

  /// What the window puts before the bar's own content: the buttons of a
  /// window that has them on the left, or the room macOS keeps for its own.
  final Widget leading;

  /// The window buttons at the right. Without them the bar ends with its
  /// own padding.
  final Widget? trailing;
  final Widget Function(Widget child)? dragArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!integrated && DesktopChromeScope.isPresent(context)) {
      return const SizedBox.shrink();
    }
    final active =
        onOpenPeerStatus == null ? null : ref.watch(activeConversationProvider);
    return Material(
      color: MoshColors.of(context).surfaceContainerLow,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          return Row(children: [
            leading,
            SizedBox(width: showChatList ? MoshSpace.s1 : MoshSpace.s3),
            if (showChatList) ...[
              _ChatListToggle(onPressed: onToggleChatList),
              const SizedBox(width: MoshSpace.s2),
            ],
            Expanded(
                child: _branding(context,
                    showName: showName && constraints.maxWidth >= 480 * scale)),
            // Beside the state pill, outside the room the window is dragged by.
            if (showName)
              Padding(
                  padding: const EdgeInsets.only(left: MoshSpace.s2),
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * _kCallPlateShare),
                      child: const TitleBarCall())),
            if (active != null)
              Padding(
                  padding: const EdgeInsets.only(left: MoshSpace.s2),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _kStatePillMaxWidth),
                    child: _StatePillSlot(
                        activeKey: active,
                        compact: constraints.maxWidth < _kCompactWidth * scale,
                        onTap: onOpenPeerStatus!),
                  )),
            if (trailing case final buttons?) ...[
              const SizedBox(width: MoshSpace.s2),
              buttons,
            ] else
              const SizedBox(width: MoshSpace.s3),
          ]);
        }),
      ),
    );
  }

  /// The mark and the name. They fill the bar between its controls, so the
  /// window is dragged by them and by the empty bar beside them.
  Widget _branding(BuildContext context, {required bool showName}) {
    final brand = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Row(children: [
        Image.asset('assets/branding/mosh-mark.png',
            width: MoshSpace.s6,
            height: MoshSpace.s6,
            excludeFromSemantics: true),
        if (showName) ...[
          const SizedBox(width: MoshSpace.s2),
          Flexible(
            child: Text(AppLocalizations.of(context)!.shellProductName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
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
      icon: const Icon(MoshIcons.listToggle),
      onPressed:
          onPressed ?? () => ref.read(railLayoutProvider.notifier).toggle(),
    );
  }
}

/// Uses existing conversation state mapping; never claims global connectivity.
///
/// The 40px minimum belongs to the button around the pill, never to the pill's
/// own surface: a stretched surface leaves the dot off center in the compact
/// state, where the label is gone and only the dot remains.
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
                        // The minimum tap target sizes the button, not the
                        // pill. Shrink-wrapping the centering keeps the button
                        // at that minimum instead of the row's full width,
                        // and keeps the dot equally spaced inside the pill.
                        child: Center(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: StatePill(
                                state: state,
                                label: label,
                                compact: compact)))),
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

/// The State pill card: tells in the title bar whether Mosh is connected.
/// A dot in the state's colour and the label, in an outlined pill; [compact]
/// shrinks it to the dot in a narrow window. The dot is green when `ready`,
/// orange while `waiting` and neutral in any other state.
class StatePill extends StatelessWidget {
  const StatePill(
      {super.key,
      required this.state,
      required this.label,
      this.compact = false});

  /// The pill's resting height; the compact badge is a circle of this size.
  static const double height = MoshSpace.s6;

  /// The raw state string ('idle' / 'waiting' / 'ready' / ...).
  final String state;

  /// The localized label (stateLabel output for dm/group; the broadcast
  /// badge text for channels).
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoshColors.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Container(
        constraints: compact
            ? const BoxConstraints.tightFor(width: height, height: height)
            : const BoxConstraints(minHeight: height),
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: MoshSpace.s3),
        decoration: ShapeDecoration(
            shape: MoshShapes.pill
                .copyWith(side: BorderSide(color: colors.outlineVariant))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: <Widget>[
            Container(
              width: MoshSpace.s2,
              height: MoshSpace.s2,
              decoration: BoxDecoration(
                color: switch (state) {
                  'ready' => colors.success,
                  'waiting' => colors.warning,
                  _ => colors.outline,
                },
                shape: BoxShape.circle,
              ),
            ),
            if (!compact) const SizedBox(width: MoshSpace.s2),
            if (!compact)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
