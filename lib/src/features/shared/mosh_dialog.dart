import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/modal_focus_trap.dart';

/// The Dialog card: a surface of the modal level that names one decision in
/// its [title], says what follows in [content] and ends with its [actions],
/// the one that goes on last. Callers own content, actions and their results.
///
/// Cancel, Escape and a press on the scrim all leave without a change, so
/// only a dialog without actions of its own has a close button.
class MoshDialog extends StatelessWidget {
  const MoshDialog({
    super.key,
    required this.title,
    required this.closeLabel,
    this.content,
    this.actions = const [],
    this.onCancel,
    this.canCancel = true,
    this.stackOnPhone = false,
  });

  final String title;

  /// Names the close button of a dialog without [actions].
  final String closeLabel;
  final Widget? content;
  final List<Widget> actions;
  final VoidCallback? onCancel;
  final bool canCancel;

  /// For answers too long to stand side by side on a phone: there they
  /// stack at full width, the main one on top.
  final bool stackOnPhone;

  void _cancel(BuildContext context) {
    if (!canCancel) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (onCancel case final callback?) {
      callback();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touch = MoshControl.touch(theme.platform);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel(context);
      },
      child: ModalFocusTrap(
        autofocus: true,
        onEscape: () => _cancel(context),
        // The theme gives the surface its level: tone, edge, corners, shadow.
        child: Dialog(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 400),
          insetPadding: EdgeInsets.all(touch ? MoshSpace.s8 : MoshSpace.s4),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            namesRoute: true,
            label: title,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(MoshSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: MoshSpace.s4,
                children: [
                  _header(context),
                  if (content case final content?)
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      child: content,
                    ),
                  if (actions.isNotEmpty) _answers(stacked: touch),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: MoshSpace.s2,
        children: [
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (actions.isEmpty)
            IconButton(
              tooltip: closeLabel,
              onPressed: canCancel ? () => _cancel(context) : null,
              icon: const Icon(MoshIcons.close),
            ),
        ],
      );

  /// The answers at the right, the main one last. Answers that do not fit
  /// the line stack with the main one on top, like the stacked phone ones.
  Widget _answers({required bool stacked}) => Padding(
        padding: const EdgeInsets.only(top: MoshSpace.s2),
        child: stacked && stackOnPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: MoshSpace.s2,
                children: actions.reversed.toList(),
              )
            : OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: MoshSpace.s2,
                overflowAlignment: OverflowBarAlignment.end,
                overflowDirection: VerticalDirection.up,
                overflowSpacing: MoshSpace.s2,
                children: actions,
              ),
      );
}

/// A destructive answer, the only red on a dialog: the error fill with the
/// ink of its own role.
ButtonStyle moshDangerButtonStyle(BuildContext context) {
  final colors = MoshColors.of(context);
  return FilledButton.styleFrom(
    backgroundColor: colors.error,
    foregroundColor: colors.onError,
  );
}
