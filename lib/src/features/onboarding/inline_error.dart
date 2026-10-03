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
