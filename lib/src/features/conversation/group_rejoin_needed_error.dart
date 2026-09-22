/// The `needs_rejoin` inline-error. Extracted from group_screen.dart to
/// keep that file under the 500-line AGENTS.md budget (the screen is the
/// only caller).
//
// Structure: a red-tinted alert box holding a bold title (with a trailing
// period) + a space + the body. The tint is derived from the theme's
// `colorScheme.error` (8% background, 35% border), 10px/14px padding and a
// 10px radius.
//
// Accessibility: `Semantics(liveRegion: true, container: true)` announces
// updates to assistive tech, which is what an inline alert does. The whole
// box is one semantic node labeled by the title + body so it reads as a
// single alert, not three nodes.
library;

import 'package:flutter/material.dart';

class GroupRejoinNeededError extends StatelessWidget {
  const GroupRejoinNeededError(
      {super.key, required this.title, required this.body});

  /// The bold title line. The trailing period is appended here, NOT in the
  /// ARB value ("Group out of sync" has no trailing period).
  final String title;

  /// The body paragraph.
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $body',
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: error.withValues(alpha: 0.35), width: 1),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$title.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: error,
                  fontSize: 12,
                ),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: error,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
