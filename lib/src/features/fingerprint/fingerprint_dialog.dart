import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';

/// The emoji quartet size inside the dialog.
const double _dialogEmojiSize = 34;

/// Vertical gaps inside the dialog body.
const double _dialogGap = 12;

/// The hex fingerprint size inside the dialog.
const double _dialogHexSize = 14;

/// Shows the fingerprint: the emoji quartet above, the hex below, then
/// the compare hint. It opens from the encryption row of a conversation's
/// details; [hint] is worded for a private chat or for a group. Both sides of a chat read the same fingerprint, so
/// the emoji match when nobody swapped the invite.
Future<void> showFingerprintDialog(
  BuildContext context, {
  required String fingerprint,
  required String hint,
}) {
  final l = AppLocalizations.of(context)!;
  final emoji = fingerprintEmoji(fingerprint).join();
  return showMoshDialog<void>(
    context: context,
    builder: (dialogContext) => MoshDialog(
      title: l.inviteFingerprintLabel,
      closeLabel: l.dialogClose,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: _dialogEmojiSize)),
          const SizedBox(height: _dialogGap),
          SelectableText(
            fingerprint,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: _dialogHexSize,
            ),
          ),
          const SizedBox(height: _dialogGap),
          Text(hint, style: Theme.of(dialogContext).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l.dialogClose),
        ),
      ],
    ),
  );
}
