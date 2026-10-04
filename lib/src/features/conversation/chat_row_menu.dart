import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_menu_item.dart';
import 'package:mosh/src/features/conversation/rename_chat_dialog.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/state/chat_names_provider.dart';

/// A secondary click or long press opens the same rename flow as the header.
class ChatRowMenu extends ConsumerWidget {
  const ChatRowMenu({super.key, required this.entry, required this.child});
  final RailEntry entry;
  final Widget child;

  bool get _canRename => switch (entry) {
        GroupRailEntry(:final group) => group.isAdmin && group.state == 'ready',
        OfferRailEntry() => false,
        _ => true,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_canRename) return child;
    final l = AppLocalizations.of(context)!;
    final enabled = entry is GroupRailEntry ||
        ref.watch(personalChatRenameAvailableProvider);
    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        MoshMenuItem(
            label: l.chatRename,
            icon: Icons.edit_outlined,
            onPressed: !enabled
                ? null
                : () => showRenameChatDialog(context, entry.ref!.target,
                    name: entry.displayName(l),
                    originalName: entry.originalName(l),
                    hasPersonalName: entry.personalName != null))
      ],
      builder: (context, controller, _) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) =>
            controller.open(position: details.localPosition),
        onLongPressStart: (details) =>
            controller.open(position: details.localPosition),
        child: child,
      ),
    );
  }
}
