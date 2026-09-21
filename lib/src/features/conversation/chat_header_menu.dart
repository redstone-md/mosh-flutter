// Mobile-only kebab menu for the three conversation headers. A
// vertical-dots button opens a dropdown of `ChatHeaderMenuAction`s. This
// widget self-gates: it renders `SizedBox.shrink()` on desktop and the real
// `PopupMenuButton` on mobile. The caller does not gate -- it always mounts
// `ChatHeaderMenu` in the AppBar `actions:` row.
//
// `PopupMenuButton` owns open/close + outside-click + Escape-to-close
// behavior. A constant vertical-dots kebab is used (no adaptive variant is
// available here); iOS would prefer a horizontal ellipsis.
//
// The filter toggle is NOT built here -- each screen builds its own action
// list (filter toggle first, then the per-screen actions) and hands the
// whole list to this widget.

library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';

/// One entry in the mobile kebab menu: an immutable value with a `label`,
/// an `icon`, an `onSelect` callback, and optional `disabled` + `danger`
/// flags (`danger` renders the menu item in the theme error color).
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

/// Mobile-only kebab menu rendering `actions` in a `PopupMenuButton`.
/// Self-gates on the mobile breakpoint (`isMobileBreakpoint`,
/// conversation_tools.dart) so it collapses to `SizedBox.shrink()` on
/// desktop. The tooltip is `l.chatMoreActions`.
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
    // Self-gate: on desktop the standalone desktop-only close/leave button
    // (gated by the caller on `!isMobileBreakpoint`) takes over.
    if (!isMobileBreakpoint(context)) return const SizedBox.shrink();
    return PopupMenuButton<ChatHeaderMenuAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: l.chatMoreActions,
      // An empty menu would show a disabled-looking kebab with no items,
      // so collapse it.
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
            // Danger tone: red label + icon.
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
