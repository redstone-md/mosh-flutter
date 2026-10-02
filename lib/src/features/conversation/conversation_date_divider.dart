import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

class ConversationDateDivider extends StatelessWidget {
  const ConversationDateDivider({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
              child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: MoshColors.bg2, borderRadius: MoshShapes.embedded),
            child: Text(
                MaterialLocalizations.of(context).formatMediumDate(date),
                style: const TextStyle(fontSize: 11, color: MoshColors.fg3)),
          )),
        ),
      );
}
