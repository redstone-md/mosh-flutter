import 'package:flutter/material.dart';

/// The Transfer bar of the Progress card: the theme's 4 px saffron bar; a
/// null [fraction] is indeterminate.
///
/// Shared by attachment transfers and the update download, so both read as the
/// same kind of waiting.
class MoshProgressBar extends StatelessWidget {
  const MoshProgressBar({
    super.key,
    required this.fraction,
    required this.semanticsLabel,
  });

  final double? fraction;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) =>
      LinearProgressIndicator(value: fraction, semanticsLabel: semanticsLabel);
}
