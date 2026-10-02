/// Conversation action menu. Flutter handles focus, dismissal and Escape.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_menu_item.dart';

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
class ChatHeaderMenu extends StatefulWidget {
  const ChatHeaderMenu({
    super.key,
    required this.actions,
    required this.l,
  });

  final List<ChatHeaderMenuAction> actions;
  final AppLocalizations l;

  @override
  State<ChatHeaderMenu> createState() => _ChatHeaderMenuState();
}

class _ChatHeaderMenuState extends State<ChatHeaderMenu> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      childFocusNode: _focus,
      consumeOutsideTap: true,
      clipBehavior: Clip.antiAlias,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        minimumSize: const WidgetStatePropertyAll(Size(220, 0)),
        maximumSize: WidgetStatePropertyAll(
            Size(360, MediaQuery.sizeOf(context).height * 0.6)),
      ),
      menuChildren: [
        for (final action in widget.actions)
          MoshMenuItem(
            label: action.label,
            icon: action.icon,
            danger: action.danger,
            onPressed: action.disabled ? null : action.onSelect,
          ),
      ],
      builder: (context, controller, _) => IconButton(
        focusNode: _focus,
        icon: const Icon(Icons.more_vert, size: 20),
        tooltip: widget.l.chatMoreActions,
        onPressed: widget.actions.isEmpty
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
