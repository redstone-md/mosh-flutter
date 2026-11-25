import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The List notice card: what the chat list says in place of its rows. An
/// empty list says what will appear and what to do next. When loading
/// [failed] the title is in the error colour, [detail] says what is safe,
/// and [onAction] under [actionLabel] offers to try again.
class RailNotice extends StatelessWidget {
  const RailNotice({
    super.key,
    required this.title,
    this.detail,
    this.failed = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? detail;
  final bool failed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: MoshSpace.s6, horizontal: MoshSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: MoshSpace.s1,
        children: [
          // One live region, so a screen reader announces a failure and
          // what follows from it together.
          Semantics(
            liveRegion: failed,
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: MoshSpace.s1,
              children: [
                Text(title,
                    style: text.titleSmall!.copyWith(
                        color: failed ? colors.error : colors.onSurface)),
                if (detail case final detail?)
                  Text(detail,
                      style: text.bodySmall!
                          .copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          if (actionLabel case final label?)
            OutlinedButton(onPressed: onAction, child: Text(label)),
        ],
      ),
    );
  }
}
