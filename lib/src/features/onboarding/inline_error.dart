// Persistent inline error for the onboarding step screens. Each step
// keeps the caught error as a widget-local `ConversationActionError?`,
// clears it at the START of the next attempt, and renders its
// `describe(l)` via this widget BELOW the primary button. This is one
// source of truth -- a transient SnackBar would auto-dismiss and would
// not be announced to assistive tech.
//
// `Semantics(liveRegion: true, container: true, excludeSemantics: true)`
// makes screen readers announce the error once when it appears; without
// excludeSemantics the visible Text would merge in and repeat the label.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Persistent inline error displayed below the primary button on the
/// onboarding step screens when a create/join handler fails.
///
/// Renders only when [message] is non-null. When null it returns
/// `const SizedBox.shrink()` so the layout below the button does not jump.
/// The error-colored `Text` is wrapped in a live-region `Semantics` whose
/// label replaces the Text's own, so screen readers announce it once.
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
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: MoshColors.dangerSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MoshColors.dangerBorder),
        ),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: MoshColors.danger),
        ),
      ),
    );
  }
}
