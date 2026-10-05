import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/message_copy.dart';

class SelectableMessageRow extends StatelessWidget {
  const SelectableMessageRow(
      {super.key,
      required this.message,
      required this.selected,
      required this.selecting,
      required this.onSelect,
      required this.onDelete,
      required this.child});
  final ConversationMessage message;
  final Set<String> selected;
  final bool selecting;
  final ValueChanged<ConversationMessage> onSelect;
  final ValueChanged<ConversationMessage> onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final available = message.messageId != null;
    final row = CopyableMessage(
        body: message.body,
        onSelect: available ? () => onSelect(message) : null,
        onDelete: available ? () => onDelete(message) : null,
        child: child);
    if (!selecting) return row;
    return Row(children: [
      SelectionContainer.disabled(
          child: Checkbox(
              value: selected.contains(message.messageId),
              semanticLabel: AppLocalizations.of(context)!.messageSelect,
              onChanged: available ? (_) => onSelect(message) : null)),
      Expanded(child: row),
    ]);
  }
}
