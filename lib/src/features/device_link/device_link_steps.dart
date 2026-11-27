import 'package:flutter/material.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/shared/step_mark.dart';
import 'package:mosh/src/rust/device_link/types.dart';

/// The steps of linking a device, counted as setup counts its own: each a
/// Link step of the Wizard step card, wrapping when the card is narrow.
class DeviceLinkSteps extends StatelessWidget {
  const DeviceLinkSteps({
    super.key,
    required this.role,
    required this.phase,
  });

  final DeviceLinkRole role;
  final DeviceLinkPhase phase;

  int get _current => switch (phase) {
        DeviceLinkPhase.awaitingApproval ||
        DeviceLinkPhase.awaitingConfirmation =>
          1,
        DeviceLinkPhase.delivering => 2,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = [
      role == DeviceLinkRole.authorizing
          ? l.deviceLinkStepShow
          : l.deviceLinkStepRead,
      l.deviceLinkStepApprove,
      l.deviceLinkStepFinish,
    ];
    // The phone sets the steps closer, so the three keep to one line where
    // their names allow it; longer ones wrap.
    final gap = isMobileBreakpoint(context) ? MoshSpace.s2 : MoshSpace.s4;
    return Wrap(spacing: gap, runSpacing: MoshSpace.s2, children: [
      for (final (index, label) in labels.indexed)
        _Step(
            label: label,
            number: index + 1,
            state: StepProgress.of(index, _current)),
    ]);
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.number, required this.state});
  final String label;
  final int number;
  final StepProgress state;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: state == StepProgress.current,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          StepMark(number: number, state: state, size: MoshSpace.s6),
          const SizedBox(width: MoshSpace.s2),
          Flexible(child: Text(label, style: stepLabelStyle(context, state))),
        ]),
      );
}
