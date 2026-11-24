import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The Value row card: a value under its label's name, the label at the left
/// and the value at the right. A fact in a settings card, a reading in
/// connection status.
class ValueRow extends StatelessWidget {
  const ValueRow({super.key, required this.label, required this.value});

  /// What the value is, already localized by the caller.
  final String label;

  /// The value: data, or localized copy.
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!;
    final colors = MoshColors.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
          minHeight:
              MoshControl.height(Theme.of(context).platform) - MoshSpace.s2),
      child: Row(children: [
        Text(label, style: style.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(width: MoshSpace.s4),
        Expanded(
          // A value cut short by the row's width stays readable in full.
          child: Tooltip(
            message: value,
            child: Text(value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: colors.onSurface)),
          ),
        ),
      ]),
    );
  }
}
