import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/rust/device_link/types.dart';

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
    return LayoutBuilder(builder: (context, size) {
      final steps = [
        for (var i = 0; i < labels.length; i++)
          _Step(label: labels[i], index: i, current: _current),
      ];
      if (size.maxWidth < 420) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final step in steps)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: step),
        ]);
      }
      return Row(children: [
        for (final step in steps) Expanded(child: step),
      ]);
    });
  }
}

class _Step extends StatelessWidget {
  const _Step(
      {required this.label, required this.index, required this.current});
  final String label;
  final int index;
  final int current;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: current == index,
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index <= current ? MoshColors.mossGlow : MoshColors.bg2,
            ),
            child: index < current
                ? const Icon(Icons.check, size: 16, color: MoshColors.moss)
                : Text('${index + 1}',
                    style: TextStyle(
                        color: index == current
                            ? MoshColors.moss
                            : MoshColors.fg3)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          index == current ? MoshColors.fg1 : MoshColors.fg3))),
        ]),
      );
}
