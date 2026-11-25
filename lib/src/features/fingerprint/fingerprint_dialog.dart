import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';

/// Shows the fingerprint as the Fingerprint kind of the Dialog card: the
/// compare hint, then a plate with the emoji quartet over the hex, as four
/// pictures are quicker to compare aloud than the digits under them. It
/// opens from the encryption row of a conversation's details; [hint] is
/// worded for a private chat or for a group. Both sides of a chat read the
/// same fingerprint, so the emoji match when nobody swapped the invite.
Future<void> showFingerprintDialog(
  BuildContext context, {
  required String fingerprint,
  required String hint,
}) {
  final l = AppLocalizations.of(context)!;
  final emoji = fingerprintEmoji(fingerprint).join(' ');
  return showMoshDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = MoshColors.of(dialogContext);
      final text = Theme.of(dialogContext).textTheme;
      return MoshDialog(
        title: l.inviteFingerprintLabel,
        closeLabel: l.dialogClose,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: MoshSpace.s4,
          children: [
            Text(hint),
            DecoratedBox(
              decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: MoshShapes.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: MoshSpace.s4),
                child: Column(spacing: MoshSpace.s2, children: [
                  Text(emoji,
                      style:
                          text.displaySmall?.copyWith(color: colors.onSurface)),
                  SelectableText(fingerprint,
                      textAlign: TextAlign.center,
                      style: text.labelLarge
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ]),
              ),
            ),
          ],
        ),
      );
    },
  );
}
