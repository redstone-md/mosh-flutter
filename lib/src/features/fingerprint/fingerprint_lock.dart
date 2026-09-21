// The Telegram-style fingerprint surface: a small lock next to the chat
// title, and the dialog it opens. There is no confirm state anywhere --
// the fingerprint is a value both sides of a chat share, so the dialog
// just shows it: the emoji quartet, the hex, and how to compare them.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';

/// Gap between the title text and the lock.
const double _lockGap = 4;

/// The lock tap area's inset: the 15px glyph plus 13px on every side keeps
/// the InkWell at 41x41 -- the audit's >=40px tap floor for a control that
/// opens the security dialog (audit 2026-09-21 hit-areas).
const double _lockTapInset = 13;

/// Lock icon size -- small enough to read as a suffix of the name, not
/// as a header action.
const double _lockIconSize = 15;

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
  });

  /// The session fingerprint the dialog shows.
  final String fingerprint;

  /// The compare hint shown inside the dialog.
  final String hint;

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
          onTap: () => showFingerprintDialog(context,
              fingerprint: fingerprint, hint: hint),
          borderRadius: BorderRadius.circular(_lockIconSize + _lockTapInset),
          child: Padding(
            // Symmetric 13px sides: the 15px glyph gets a 41x41 tap box.
            // Chat headers are 70px (54 compact), so the box fits the title
            // row.
            padding: const EdgeInsets.all(_lockTapInset),
            child: Icon(
              Icons.lock,
              size: _lockIconSize,
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
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.inviteFingerprintLabel),
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
