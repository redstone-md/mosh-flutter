import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart';

/// 4px moss progress on bg-3; a null [fraction] is indeterminate.
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
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 4,
          backgroundColor: MoshColors.bg3,
          color: MoshColors.moss,
          semanticsLabel: semanticsLabel,
        ),
      );
}
