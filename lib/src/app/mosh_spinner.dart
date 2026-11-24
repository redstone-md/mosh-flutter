import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';

/// The small spinner of the Progress card, 16 px, in the colour an icon
/// would take in its place: a wait inside a control.
///
/// In a button it is the Loading state of the Button card. It takes the
/// place of the leading icon, the label stays and the press is blocked:
///
/// ```dart
/// FilledButton.icon(
///   onPressed: busy ? MoshSpinner.blockPress : _join,
///   icon: busy ? const MoshSpinner() : null,
///   label: Text(l.join),
/// )
/// ```
class MoshSpinner extends StatelessWidget {
  const MoshSpinner({super.key});

  /// `onPressed` of a loading button. It is not null, so the button keeps its
  /// colours instead of turning disabled, and it does nothing.
  static void blockPress() {}

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: MoshSpace.s4,
        child: CircularProgressIndicator(
          strokeWidth: MoshBorder.thick,
          color: IconTheme.of(context).color,
        ),
      );
}
