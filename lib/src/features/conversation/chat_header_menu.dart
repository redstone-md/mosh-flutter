/// Conversation action menu. Flutter handles focus, dismissal and Escape.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';

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

/// Shared action menu on desktop and mobile.
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
    return PopupMenuButton<ChatHeaderMenuAction>(
      clipBehavior: Clip.antiAlias,
      icon: const Icon(Icons.more_vert, size: 20),
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
