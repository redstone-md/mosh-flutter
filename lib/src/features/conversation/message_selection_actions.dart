import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/conversation/message_selection.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';

/// The same supported actions in the desktop header and mobile footer.
class MessageSelectionActions extends StatelessWidget {
  const MessageSelectionActions({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = MessageSelectionScope.maybeOf(context)!;
    final selection = scope.selection;
    final enabled = !selection.busy && selection.count > 0;
    final text = scope.selectedText();
    final l = AppLocalizations.of(context)!;
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          TextButton.icon(
            onPressed: enabled && text.isNotEmpty ? scope.onCopySelected : null,
            icon: const Icon(Icons.copy_outlined),
            label: Text(l.nativeMenuCopy),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          FilledButton.icon(
            onPressed: enabled ? scope.onDeleteSelected : null,
            icon: const Icon(Icons.delete_outline),
            label: Text(l.messageSelectionDelete),
            style: moshDangerButtonStyle().copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(48, 48))),
          ),
        ]);
  }
}

/// Hides the narrow composer without losing its draft or mounted controls.
class MessageSelectionComposer extends StatelessWidget {
  const MessageSelectionComposer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selection = MessageSelectionScope.maybeOf(context)?.selection;
    final selecting =
        isMobileBreakpoint(context) && (selection?.active ?? false);
    final colors = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Visibility(visible: !selecting, maintainState: true, child: child),
      if (selecting)
        Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: const MessageSelectionActions(),
        ),
    ]);
  }
}
