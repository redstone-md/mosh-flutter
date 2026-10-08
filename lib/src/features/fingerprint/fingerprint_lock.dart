import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';

/// The lock tap area's inset: the 15px glyph plus 13px on every side keeps
/// the InkWell at 41x41 -- the audit's >=40px tap floor for a control that
/// opens the security dialog (audit 2026-09-21 hit-areas).
const double _lockTapInset = 13;

/// Standalone lock icon size.
const double _lockIconSize = 15;

/// A quieter suffix on the nickname, inside a compact 24px target.
const double _inlineLockIconSize = 12;

/// The emoji quartet size inside the dialog.
const double _dialogEmojiSize = 34;

/// Vertical gaps inside the dialog body.
const double _dialogGap = 12;

/// The hex fingerprint size inside the dialog.
const double _dialogHexSize = 14;

/// A small lock rendered next to the peer or group name in the chat
/// header. Tapping it opens [showFingerprintDialog].
///
/// Renders nothing while [fingerprint] is empty (a session that has
/// not resolved yet). [hint] is the dialog's compare hint -- DM and
/// group headers pass their own wording.
class FingerprintLock extends StatelessWidget {
  const FingerprintLock({
    super.key,
    required this.fingerprint,
    required this.hint,
    this.besideName = false,
  });

  /// The session fingerprint the dialog shows.
  final String fingerprint;

  /// The compare hint shown inside the dialog.
  final String hint;
  final bool besideName;

  @override
  Widget build(BuildContext context) {
    if (fingerprint.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Semantics(
      label: l.cryptoNoticeTitle,
      button: true,
      child: Tooltip(
        message: l.cryptoNoticeTitle,
        child: InkWell(
          onTap: () => showFingerprintDialog(
            context,
            fingerprint: fingerprint,
            hint: hint,
          ),
          borderRadius: besideName ? MoshShapes.embedded : MoshShapes.control,
          child: Padding(
            // Align the inline glyph with the name's first line.
            padding: besideName
                ? const EdgeInsets.all(6)
                : const EdgeInsets.all(_lockTapInset),
            child: Icon(
              Icons.lock,
              size: besideName ? _inlineLockIconSize : _lockIconSize,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the fingerprint: the emoji quartet above, the hex below, then
/// the compare hint. Both sides of a chat read the same fingerprint, so
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
