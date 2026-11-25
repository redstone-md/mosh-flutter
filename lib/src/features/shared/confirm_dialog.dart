import 'package:flutter/material.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';

/// Confirmation requires an explicit action; initial focus stays on
/// cancellation. What it confirms is [destructive] unless said otherwise:
/// the answer that goes on is then the dialog's only red.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.cancelLabel,
    required this.onCancel,
    required this.onConfirm,
    this.destructive = true,
  });

  final String title;
  final String body;
  final String confirmLabel;

  /// Localized cancellation label used by both the button and close control.
  final String? cancelLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool destructive;

  static const String defaultCancelLabel = 'Cancel';

  @override
  Widget build(BuildContext context) {
    final cancel = cancelLabel ?? defaultCancelLabel;
    return MoshDialog(
      title: title,
      closeLabel: cancel,
      onCancel: onCancel,
      content: Text(body),
      actions: [
        TextButton(onPressed: onCancel, child: Text(cancel)),
        FilledButton(
          onPressed: onConfirm,
          style: destructive ? moshDangerButtonStyle(context) : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Only the confirmation button returns true; all dismissal paths return false.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = true,
}) async {
  final cancel = cancelLabel ?? ConfirmDialog.defaultCancelLabel;
  final result = await showMoshDialog<bool>(
    context: context,
    barrierLabel: cancel,
    builder: (dialogContext) => ConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancel,
      destructive: destructive,
      onCancel: () => Navigator.of(dialogContext).pop(false),
      onConfirm: () => Navigator.of(dialogContext).pop(true),
    ),
  );
  return result ?? false;
}
