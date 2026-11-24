import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/step_mark.dart';

import 'first_run_profile.dart';

/// The Setup progress card: setup is a real sequence of three, so it counts
/// its steps. Done ones are ticked, the current one is filled, and the line
/// between two marks is lit once the later one is reached.
class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step});
  final SetupStep step;

  /// The widest the progress is drawn.
  static const double maxWidth = 360;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = [
      l.firstRunNameStep,
      l.firstRunDeviceStep,
      l.firstRunNetworkStep
    ];
    return Semantics(
        liveRegion: true,
        label: l.firstRunProgress(step.index + 1, 3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: LayoutBuilder(builder: (context, constraints) {
            // Too narrow for three names: the marks alone, and the current
            // step's name under them.
            final marksOnly = constraints.maxWidth <
                300 * MediaQuery.textScalerOf(context).scale(14) / 14;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (index, label) in labels.indexed) ...[
                  if (index > 0) _line(context, reached: index <= step.index),
                  _item(context, index, marksOnly ? null : label),
                ],
              ]),
              if (marksOnly) ...[
                const SizedBox(height: MoshSpace.s1),
                Text(labels[step.index],
                    style: stepLabelStyle(context, StepProgress.current)),
              ],
            ]);
          }),
        ));
  }

  Widget _item(BuildContext context, int index, String? label) {
    final state = StepProgress.of(index, step.index);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      StepMark(number: index + 1, state: state),
      if (label != null) ...[
        const SizedBox(height: MoshSpace.s1),
        Text(label, style: stepLabelStyle(context, state)),
      ],
    ]);
  }

  /// The line between two marks, level with their middle.
  Widget _line(BuildContext context, {required bool reached}) {
    final colors = MoshColors.of(context);
    return Expanded(
      child: Container(
        height: MoshBorder.thick,
        margin: const EdgeInsets.symmetric(
            horizontal: MoshSpace.s2,
            vertical: (MoshSpace.s8 - MoshBorder.thick) / 2),
        color: reached ? colors.primary : colors.outlineVariant,
      ),
    );
  }
}
