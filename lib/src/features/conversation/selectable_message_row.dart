import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/conversation/message_copy.dart';
import 'package:mosh/src/features/conversation/message_selection.dart';

/// One message row of the feed, at the feed's side padding and its place
/// in the rhythm of the runs: bubbles of one run sit 4 px apart and a new
/// run starts 12 px lower.
///
/// While messages are picked every row leads with a checkbox, a tap
/// anywhere on the row picks it, Shift extends from the last pick, and the
/// row's own controls rest. A picked row carries a band across the feed.
/// The tree keeps one shape in both modes, so rows never remount.
class SelectableMessageRow extends StatelessWidget {
  const SelectableMessageRow(
      {super.key,
      required this.message,
      required this.child,
      this.grouped = false});
  final ConversationMessage message;

  /// Whether the row continues the run above it.
  final bool grouped;
  final Widget child;

  /// What the band of a picked row keeps above and below its bubble; two
  /// picked rows of one run meet.
  static const double _band = MoshSpace.s1 / 2;

  @override
  Widget build(BuildContext context) {
    final scope = MessageSelectionScope.maybeOf(context);
    final selection = scope?.selection;
    final id = scope == null ? null : message.messageId;
    final selecting = selection?.active ?? false;
    final selected = id != null && selection!.isSelected(id);
    final side = feedPadding(compact: isMobileBreakpoint(context)).left;
    return Padding(
      padding: EdgeInsets.only(top: messageRowSpacing(grouped) - 2 * _band),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selecting && id != null ? () => _pick(selection!, id) : null,
        child: ColoredBox(
          color: selecting && selected
              ? MoshColors.of(context).secondaryContainer
              : Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: side, vertical: _band),
            child: Row(
              spacing: MoshSpace.s2,
              children: [
                if (selecting && id != null)
                  // The Checkbox card's 24 px mark.
                  Transform.scale(
                    scale: MoshSpace.s6 / Checkbox.width,
                    child: Checkbox(
                      key: ValueKey('message-selector-$id'),
                      value: selected,
                      semanticLabel:
                          AppLocalizations.of(context)!.messageSelect,
                      onChanged:
                          selection!.busy ? null : (_) => _pick(selection, id),
                    ),
                  ),
                Expanded(
                  child: CopyableMessage(
                    key: ValueKey(message.messageId ?? message),
                    body: message.body,
                    selectionId: id,
                    selecting: selecting,
                    selected: selecting && id != null ? selected : null,
                    onSelect: id == null ? null : () => selection!.toggle(id),
                    onDelete:
                        id == null ? null : () => scope!.onDelete(message),
                    child: ExcludeFocus(
                      excluding: selecting,
                      child: AbsorbPointer(absorbing: selecting, child: child),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pick(MessageSelection selection, String id) =>
      HardwareKeyboard.instance.isShiftPressed
          ? selection.extendTo(id)
          : selection.toggle(id);
}
