import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show chatHeaderHeight;

/// Replaces the chat header while messages are selected: the bulk action on
/// the left, the way out on the right.
class MessageSelectionBar extends StatelessWidget {
  const MessageSelectionBar({
    super.key,
    required this.count,
    required this.busy,
    required this.onDelete,
    required this.onCancel,
  });

  final int count;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final compact = MediaQuery.sizeOf(context).width <= 640;
    final button = FilledButton(
      onPressed: busy || count == 0 ? null : onDelete,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(l.messageSelectionDelete),
        const SizedBox(width: 8),
        Opacity(opacity: 0.72, child: Text('$count')),
      ]),
    );
    return AppBar(
      toolbarHeight: chatHeaderHeight(context),
      automaticallyImplyLeading: false,
      titleSpacing: compact ? 8 : 22,
      title: Semantics(
        liveRegion: true,
        label: l.messagesSelected(count),
        child: Align(alignment: Alignment.centerLeft, child: button),
      ),
      actions: [
        Padding(
          padding: EdgeInsets.only(right: compact ? 8 : 16),
          child: TextButton(
              onPressed: busy ? null : onCancel, child: Text(l.dialogCancel)),
        ),
      ],
    );
  }
}
