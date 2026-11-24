import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Where a step of a counted flow stands: behind, at hand or ahead.
enum StepProgress {
  done,
  current,
  upcoming;

  /// The state of step [index] while the flow is at step [current].
  static StepProgress of(int index, int current) => index < current
      ? done
      : index == current
          ? StepProgress.current
          : upcoming;
}

/// The numbered mark of a step in the Wizard step card: a done one is ticked
/// on a quiet plate, the current one is filled with the accent, one ahead is
/// an outlined number. [size] is 32 px in setup and 24 px in device linking.
class StepMark extends StatelessWidget {
  const StepMark(
      {super.key,
      required this.number,
      required this.state,
      this.size = MoshSpace.s8});

  final int number;
  final StepProgress state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final (fill, ink) = switch (state) {
      StepProgress.done => (
          colors.secondaryContainer,
          colors.onSecondaryContainer
        ),
      StepProgress.current => (colors.primary, colors.onPrimary),
      StepProgress.upcoming => (null, colors.onSurfaceMuted),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: fill == null ? Border.all(color: colors.outline) : null),
      child: state == StepProgress.done
          ? Icon(MoshIcons.check, size: MoshSpace.s4, color: ink)
          : Text('$number',
              // The mark keeps its size, so its number does too.
              textScaler: TextScaler.noScaling,
              style:
                  Theme.of(context).textTheme.labelLarge!.copyWith(color: ink)),
    );
  }
}

/// A step's name beside or under its mark: quiet while the step is ahead.
TextStyle stepLabelStyle(BuildContext context, StepProgress state) {
  final colors = MoshColors.of(context);
  return Theme.of(context).textTheme.labelMedium!.copyWith(
      color: state == StepProgress.upcoming
          ? colors.onSurfaceMuted
          : colors.onSurface);
}
