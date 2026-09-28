import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';

Future<bool> confirmDeviceRemoval(BuildContext context, String name) async {
  final l = AppLocalizations.of(context)!;
  return showConfirmDialog(
    context: context,
    title: l.deviceLinkRemoveTitle(name),
    body: l.deviceLinkRemoveBody,
    cancelLabel: l.dialogCancel,
    confirmLabel: l.deviceLinkRemove,
  );
}
