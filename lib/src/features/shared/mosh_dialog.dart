import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/modal_focus_trap.dart';

/// Ordinary dialog layout; callers own content, actions and their results.
class MoshDialog extends StatelessWidget {
  const MoshDialog({
    super.key,
    required this.title,
    required this.closeLabel,
    this.content,
    this.actions = const [],
    this.onCancel,
    this.canCancel = true,
  });

  final String title;
  final String closeLabel;
  final Widget? content;
  final List<Widget> actions;
  final VoidCallback? onCancel;
  final bool canCancel;

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel(context);
      },
      child: ModalFocusTrap(
        autofocus: true,
        onEscape: () => _cancel(context),
        child: AlertDialog(
          semanticLabel: title,
          scrollable: true,
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: theme.colorScheme.outline),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 16, 14, 0),
          titleTextStyle: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
          title: _header(context),
          contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
          contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13.5,
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          content: content,
          actionsPadding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          actionsOverflowButtonSpacing: 8,
          actions: actions,
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          IconButton(
            tooltip: closeLabel,
            onPressed: canCancel ? () => _cancel(context) : null,
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.standard,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      );
}

/// Destructive actions retain readable ink even on custom danger fills.
ButtonStyle moshDangerButtonStyle([Color color = MoshColors.danger]) =>
    FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: color.computeLuminance() > 0.183
          ? MoshColors.mossInk
          : MoshColors.fg1,
    );
