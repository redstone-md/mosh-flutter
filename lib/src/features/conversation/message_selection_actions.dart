import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
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
        spacing: MoshSpace.s2,
        runSpacing: MoshSpace.s2,
        alignment: WrapAlignment.center,
        children: [
          TextButton.icon(
            onPressed: enabled && text.isNotEmpty ? scope.onCopySelected : null,
            icon: const Icon(MoshIcons.copy),
            label: Text(l.nativeMenuCopy),
          ),
          FilledButton.icon(
            onPressed: enabled ? scope.onDeleteSelected : null,
            icon: const Icon(MoshIcons.delete),
            label: Text(l.messageSelectionDelete),
            style: moshDangerButtonStyle(context),
          ),
        ]);
  }
}

/// The Selection actions card: on the phone the actions take the composer's
/// place at the bottom, within reach of the thumb. The composer is hidden
/// without losing its draft or its mounted controls.
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
          padding: const EdgeInsets.symmetric(
              horizontal: MoshSpace.s3, vertical: MoshSpace.s2),
          color: colors.surface,
          child: const MessageSelectionActions(),
        ),
    ]);
  }
}
