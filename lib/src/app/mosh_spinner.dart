import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';

/// The small spinner of the Progress card, 16 px, in the colour an icon
/// would take in its place: a wait inside a control.
class MoshSpinner extends StatelessWidget {
  const MoshSpinner({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: MoshSpace.s4,
        child: CircularProgressIndicator(
          strokeWidth: MoshBorder.thick,
          color: IconTheme.of(context).color,
        ),
      );
}

/// The Loading state of the Button card: while [loading], the button in
/// [child] keeps its label and its colours and takes no press, from the
/// pointer or the keyboard. The button shows a [MoshSpinner] as its icon:
///
/// ```dart
/// MoshLoading(
///   loading: busy,
///   child: FilledButton.icon(
///     onPressed: _join,
///     icon: busy ? const MoshSpinner() : null,
///     label: Text(l.join),
///   ),
/// )
/// ```
class MoshLoading extends StatelessWidget {
  const MoshLoading({super.key, required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: loading,
        child: ExcludeFocus(excluding: loading, child: child),
      );
}
