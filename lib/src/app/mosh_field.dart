import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';
import 'mosh_theme.dart';

/// The Text field and Select cards' label: it stands above the well and
/// stays there while the user types. [child] is the well, a [TextField] or
/// the button of a select, and is announced under [label].
class MoshField extends StatelessWidget {
  const MoshField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(label,
              style: text.labelMedium!
                  .copyWith(color: MoshColors.of(context).onSurfaceVariant)),
        ),
        const SizedBox(height: MoshSpace.s2),
        Semantics(
          label: label,
          // A text field sets its value in the theme's bodyLarge; the card
          // sets it in bodyMedium.
          child: Theme(
            data: theme.copyWith(
                textTheme: text.copyWith(bodyLarge: text.bodyMedium)),
            child: child,
          ),
        ),
      ],
    );
  }
}
