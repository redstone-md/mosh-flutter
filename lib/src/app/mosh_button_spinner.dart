import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';

/// The Loading state of the Button card: the spinner takes the place of the
/// leading icon, the label stays and the press is blocked.
///
/// ```dart
/// FilledButton.icon(
///   onPressed: busy ? MoshButtonSpinner.blockPress : _join,
///   icon: busy ? const MoshButtonSpinner() : null,
///   label: Text(l.join),
/// )
/// ```
class MoshButtonSpinner extends StatelessWidget {
  const MoshButtonSpinner({super.key});

  /// `onPressed` of a loading button. It is not null, so the button keeps its
  /// colours instead of turning disabled, and it does nothing.
  static void blockPress() {}

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: MoshSpace.s4,
        child: CircularProgressIndicator(
          strokeWidth: MoshBorder.thick,
          // The button's own content colour, as an icon would take it.
          color: IconTheme.of(context).color,
        ),
      );
}
