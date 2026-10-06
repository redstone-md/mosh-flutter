import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/message_copy.dart';
import 'package:mosh/src/features/conversation/message_selection.dart';

/// One message row. While messages are picked, a tap anywhere on the row
/// picks it, Shift extends from the last pick, and the row's own controls
/// rest. The tree keeps one shape in both modes, so rows never remount.
class SelectableMessageRow extends StatelessWidget {
  const SelectableMessageRow(
      {super.key, required this.message, required this.child});
  final ConversationMessage message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = MessageSelectionScope.maybeOf(context);
    final selection = scope?.selection;
    final id = scope == null ? null : message.messageId;
    final selecting = selection?.active ?? false;
    final selected = id != null && selection!.isSelected(id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selecting && id != null ? () => _pick(selection!, id) : null,
      child: ColoredBox(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        child: CopyableMessage(
          key: ValueKey(message.messageId ?? message),
          body: message.body,
          selectionId: id,
          selecting: selecting,
          selected: selecting && id != null ? selected : null,
          onSelect: id == null ? null : () => selection!.toggle(id),
          onDelete: id == null ? null : () => scope!.onDelete(message),
          child: AbsorbPointer(absorbing: selecting, child: child),
        ),
      ),
    );
  }

  void _pick(MessageSelection selection, String id) =>
      HardwareKeyboard.instance.isShiftPressed
          ? selection.extendTo(id)
          : selection.toggle(id);
}
