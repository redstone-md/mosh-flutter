import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';
import 'mosh_theme.dart';

/// The Text field card's label: it stands above the well and stays there
/// while the user types. [child] is the well, a [TextField], and is
/// announced under [label]. The label fades with a well that is not
/// [enabled].
class MoshField extends StatelessWidget {
  const MoshField(
      {super.key,
      required this.label,
      required this.child,
      this.enabled = true});

  final String label;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final ink = MoshColors.of(context).onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(label,
              style: text.labelMedium!.copyWith(
                  color: enabled
                      ? ink
                      : MoshState.tint(ink, MoshState.disabledContent))),
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
