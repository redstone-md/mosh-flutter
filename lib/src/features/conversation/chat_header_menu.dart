// Mobile-only kebab menu for the three conversation headers, 1-1 with
// React `ChatHeaderMenu` (src/features/private-dm/ChatHeaderMenu.tsx). A
// vertical-dots (`IconDotsVertical`) button opens a dropdown of
// `ChatHeaderMenuAction`s. React applies `.chat-more .chat-mobile-only` ON
// the menu div itself (ChatHeaderMenu.tsx ~L57), so this widget self-gates:
// it renders `SizedBox.shrink()` on desktop and the real `PopupMenuButton`
// on mobile. The caller does not gate -- it always mounts `ChatHeaderMenu`
// in the AppBar `actions:` row (mirroring React always rendering
// `<ChatHeaderMenu actions={actions} />` inside `chat-header-actions`).
//
// `PopupMenuButton` is the idiomatic Flutter equivalent of React's custom
// dropdown: it owns open/close + outside-click + the Escape-to-close
// behavior React hand-rolls with the `pointerdown`/`keydown` listeners
// (ChatHeaderMenu.tsx ~L20-39). `Icons.adaptive_more_vert` maps to a
// `Icons.more_vert` is the closest Material equivalent to tabler's
// `IconDotsVertical` (this Flutter SDK ships no `adaptive_more_vert`; a
// constant kebab is the spec's listed fallback). A vertical-dots kebab
// matches the React icon on Android; iOS would prefer a horizontal
// ellipsis, but no adaptive variant is available here.
//
// The filter toggle is NOT built here -- React prepends it in
// `conversationMenuActions` (ActiveChatHeader.tsx ~L155-170) at the call
// site, so each screen builds its own action list (filter toggle first,
// then the per-screen actions) and hands the whole list to this widget.

library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';

/// One entry in the mobile kebab menu, 1-1 with React
/// `ChatHeaderMenuAction` (ChatHeaderMenu.tsx ~L5-12): an immutable value
/// with a `label`, an `icon`, an `onSelect` callback, and optional
/// `disabled` + `danger` flags (React `disabled?` + `tone?: "danger"`).
/// `icon` is an `IconData` here (Flutter uses `Icons`, not ReactNode);
/// `danger` replaces React's `tone === "danger"` (the menu item renders
/// in the theme error color).
@immutable
class ChatHeaderMenuAction {
  const ChatHeaderMenuAction({
    required this.label,
    required this.icon,
    required this.onSelect,
    this.disabled = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelect;
  final bool disabled;
  final bool danger;
}

/// Mobile-only kebab menu rendering `actions` in a `PopupMenuButton`, 1-1
/// with React `ChatHeaderMenu` (ChatHeaderMenu.tsx). Self-gates on the
/// mobile breakpoint (`isMobileBreakpoint`, conversation_tools.dart) so it
/// collapses to `SizedBox.shrink()` on desktop -- mirroring React's
/// `.chat-mobile-only` class applied to the menu div itself. The tooltip
/// / aria-label is `l.chatMoreActions` (React `aria-label="More chat
/// actions"`).
class ChatHeaderMenu extends StatelessWidget {
  const ChatHeaderMenu({
    super.key,
    required this.actions,
    required this.l,
  });

  final List<ChatHeaderMenuAction> actions;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    // Self-gate: React `.chat-more .chat-mobile-only` hides the menu div on
    // desktop; on desktop the standalone desktop-only close/leave button
    // (gated by the caller on `!isMobileBreakpoint`) takes over.
    if (!isMobileBreakpoint(context)) return const SizedBox.shrink();
    return PopupMenuButton<ChatHeaderMenuAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: l.chatMoreActions,
      // React renders nothing when `actions` is empty; an empty menu would
      // show a disabled-looking kebab with no items, so collapse it.
      enabled: actions.isNotEmpty,
      onSelected: (action) {
        if (action.disabled) return;
        action.onSelect();
      },
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<ChatHeaderMenuAction>(
            value: action,
            enabled: !action.disabled,
            // Danger tone: red label + icon, 1-1 with React's
            // `chat-more-item-danger` class (ChatHeaderMenu.tsx ~L47-50).
            child: action.danger
                ? DefaultTextStyle.merge(
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    child: Row(
                      children: [
                        Icon(action.icon,
                            size: 18,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(action.label,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Icon(action.icon, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child:
                            Text(action.label, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
