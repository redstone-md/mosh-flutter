import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';

/// The line a call says about itself beside the name: how it is going, or
/// with a [tone] the warning or error that takes that place where the call
/// is minimized.
class CallLine {
  const CallLine(this.text, {this.tone, this.fontFeatures});

  final String text;
  final MoshNoticeTone? tone;
  final List<FontFeature>? fontFeatures;

  Color ink(MoshColors c) => switch (tone) {
        MoshNoticeTone.error => c.error,
        MoshNoticeTone.warning => c.warning,
        _ => c.onSurfaceVariant,
      };
}

/// Who a call is with and the line about it, side by side on one baseline:
/// on a plate over video, in the title bar and in the phone's strip, which
/// is [wide] and gives the line all the room the name leaves.
class CallWhoLine extends StatelessWidget {
  const CallWhoLine(
      {super.key, required this.peer, required this.line, this.wide = false});

  final String peer;
  final CallLine line;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    final status = Text(line.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (wide ? text.bodySmall : text.labelMedium)?.copyWith(
            color: line.ink(colors), fontFeatures: line.fontFeatures));
    return Row(
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        spacing: MoshSpace.s2,
        children: [
          Flexible(
              child: Text(peer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (wide ? text.titleSmall : text.labelLarge)
                      ?.copyWith(color: colors.onSurface))),
          wide ? Expanded(child: status) : Flexible(child: status),
        ]);
  }
}
