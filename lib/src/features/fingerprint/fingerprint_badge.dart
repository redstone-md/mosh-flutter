// Fingerprint verification badge shown in the DM screen app bar, ported 1:1
// from the React `FingerprintBadge` (src/features/private-dm/
// ActiveChatHeader.tsx).
//
// Purely client-side: there is NO Rust/Gateway confirm-fingerprint call.
// Like the React component, verification is a local `Set<String>` of
// confirmed session IDs held by `_DmScreenState` (mirrors React's
// `confirmedFingerprints` useState in use-chat-close-flow.ts). This widget
// only renders the badge and fires `onConfirm`; it owns no state.
//
// Renders nothing when `fingerprint` is empty (React `if (!fingerprint)
// return null`). The displayed text is the first 4 groups of 4 chars,
// space-joined (React `fingerprint.match(/.{1,4}/g)?.slice(0, 4).join(" ")`).
//
// `confirmed` swaps the visual style (green tint + disabled), the tooltip
// (`inviteConfirmedButton` vs `inviteFingerprintHint`), and the semantics
// label (`inviteConfirmedButton` vs `inviteConfirmButton`), and disables
// the tap (React `onClick={confirmed ? undefined : onConfirm}`). The ARB
// keys are reused as-is; no new keys are added.
library;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';

/// The compact pill regex pattern ported from React `.{1,4}`.
final RegExp _fingerprintGroup = RegExp(r'.{1,4}');

/// A small, monospace fingerprint pill with a shield icon. Mirrors the
/// React `fingerprint-badge` (desktop-shell.css): a 999px-radius pill,
/// `--line` border, neutral fill when unconfirmed; the
/// `fingerprint-badge-confirmed` class tints text + border green and
/// removes the hover/tap affordance.
class FingerprintBadge extends StatelessWidget {
  const FingerprintBadge({
    super.key,
    required this.fingerprint,
    required this.confirmed,
    required this.onConfirm,
  });

  /// The raw session fingerprint (may be empty -> renders nothing).
  final String fingerprint;

  /// Whether this session's fingerprint has been confirmed locally.
  final bool confirmed;

  /// Fires on tap when NOT confirmed; ignored when confirmed.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    if (fingerprint.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final display = _fingerprintGroup
        .allMatches(fingerprint)
        .take(4)
        .map((m) => m[0]!)
        .join(' ');
    // React `.fingerprint-badge { border: 1px solid var(--line);
    // background: var(--bg-2); color: var(--warn) }`, with
    // `.fingerprint-badge-confirmed` swapping the text to --moss over a
    // rgba(moss,0.3) border. The unconfirmed state is a WARNING, so it is
    // --warn rather than a neutral outline.
    final accent = confirmed ? MoshColors.moss : MoshColors.warn;
    final border =
        confirmed ? MoshColors.moss.withValues(alpha: 0.3) : MoshColors.line;
    return Semantics(
      label: confirmed ? l.inviteConfirmedButton : l.inviteConfirmButton,
      button: true,
      enabled: !confirmed,
      child: Tooltip(
        message: confirmed ? l.inviteConfirmedButton : l.inviteFingerprintHint,
        child: InkWell(
          onTap: confirmed ? null : onConfirm,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: MoshColors.bg2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  display,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
