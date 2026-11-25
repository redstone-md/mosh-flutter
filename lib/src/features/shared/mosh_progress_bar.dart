import 'package:flutter/material.dart';

/// The Transfer bar of the Progress card: the theme's 4 px saffron bar; a
/// null [fraction] is indeterminate.
///
/// Shared by attachment transfers and the update download, so both read as the
/// same kind of waiting. In a bubble the bar takes the bubble's inks, as its
/// own amber would vanish on a message the user sent: [color] and [track].
class MoshProgressBar extends StatelessWidget {
  const MoshProgressBar({
    super.key,
    required this.fraction,
    required this.semanticsLabel,
    this.color,
    this.track,
  });

  final double? fraction;
  final String semanticsLabel;
  final Color? color, track;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
      value: fraction,
      semanticsLabel: semanticsLabel,
      color: color,
      backgroundColor: track);
}
