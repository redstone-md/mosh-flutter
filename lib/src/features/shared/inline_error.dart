import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The Inline error of the Text field card: the error mark and what to fix,
/// in the error colour: below the primary button of an onboarding step when
/// a create/join handler fails, and under a select whose choices did not load.
///
/// Renders only when [message] is non-null. When null it returns
/// `const SizedBox.shrink()` so the layout below the button does not jump.
/// The row is wrapped in a live-region `Semantics` whose
/// label replaces the Text's own, so screen readers announce it once.
class InlineError extends StatelessWidget {
  const InlineError({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      container: true,
      label: text,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(MoshIcons.error, size: MoshSpace.s4, color: colors.error),
          const SizedBox(width: MoshSpace.s1),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}
