/// The `needs_rejoin` inline-error -- 1-в-1 with React's
/// `<div className="inline-error" role="alert">` fragment
/// (ActiveChatPanes.tsx L355-360). Extracted from group_screen.dart to keep
/// that file under the 500-line AGENTS.md budget (the screen is the only
/// caller; React renders this fragment only in the group pane).
//
// Structure: a red-tinted alert box holding `<strong>{rejoinNeededTitle}.</strong>`
// (bold, with the period React appends via `<strong>{title}.</strong>`) + a
// space + the body. The tint mirrors React's `.inline-error` CSS
// (desktop-shell.css L1066-1073): `padding: 10px 14px`, `border-radius: 10px`,
// `background: rgba(232,106,90,0.08)`, `border: 1px solid rgba(232,106,90,0.35)`,
// `color: var(--danger)`, `font-size: 12px`. Material's `colorScheme.error` is
// the idiomatic Flutter equivalent of `--danger`, so the tint is derived from
// it (8% bg, 35% border) to match React's rgba alphas.
//
// Accessibility: React sets `role="alert"`. Flutter has no direct `alert`
// role; `Semantics(liveRegion: true, container: true)` is the closest
// equivalent -- a live region announces updates to assistive tech, which is
// what an inline alert does. The whole box is one semantic node labeled by
// the title + body so it reads as a single alert, not three nodes.
library;

import 'package:flutter/material.dart';

class GroupRejoinNeededError extends StatelessWidget {
  const GroupRejoinNeededError({super.key, required this.title, required this.body});

  /// The bold title line. React renders `<strong>{title}.</strong>` -- the
  /// period is appended by React, NOT in the ARB value ("Group out of sync"
  /// has no trailing period). We append `.` here in the bold span to match.
  final String title;

  /// The body paragraph (React `{rejoinNeededBody}`).
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

