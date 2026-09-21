// Persistent inline error for the onboarding step screens. Each step
// keeps the caught error as a widget-local `ConversationActionError?`,
// clears it at the START of the next attempt, and renders its
// `describe(l)` via this widget BELOW the primary button. This is one
// source of truth -- a transient SnackBar would auto-dismiss and would
// not be announced to assistive tech.
//
// `Semantics(liveRegion: true, container: true)` makes screen readers
// announce the error when it appears; the same pattern invite_paste's
// `_DetectBadge` and diagnostics `RuntimeError` already use in this repo.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Persistent inline error displayed below the primary button on the
/// onboarding step screens when a create/join handler fails.
///
/// Renders only when [message] is non-null. When null it returns
/// `const SizedBox.shrink()` so the layout below the button does not jump.
/// The error-colored `Text` is wrapped in `Semantics(liveRegion: true,
/// container: true, label: message)` so screen readers announce it when it
/// appears.
class InlineError extends StatelessWidget {
  const InlineError({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      container: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: MoshColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: MoshColors.danger.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: MoshColors.danger),
        ),
      ),
    );
  }
}
