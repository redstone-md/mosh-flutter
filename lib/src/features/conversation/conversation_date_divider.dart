import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The Date divider card: a new day in the feed, a quiet pill in the
/// middle of it.
class ConversationDateDivider extends StatelessWidget {
  const ConversationDateDivider({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.only(top: MoshSpace.s3, bottom: MoshSpace.s2),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: MoshSpace.s3, vertical: MoshSpace.s1),
            decoration: ShapeDecoration(
                color: colors.surfaceContainerHigh, shape: MoshShapes.pill),
            child: Text(
                MaterialLocalizations.of(context).formatMediumDate(date),
                style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
      ),
    );
  }
}
