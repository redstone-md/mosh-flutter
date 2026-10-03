import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'first_run_profile.dart';
import 'first_run_heading.dart';
import 'first_run_sizing.dart';

class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step, this.compact = false});
  final SetupStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = [
      l.firstRunNameStep,
      l.firstRunDeviceStep,
      l.firstRunNetworkStep
    ];
    final diameter = (MediaQuery.textScalerOf(context).scale(14) + 16)
        .clamp(compact ? 32.0 : 40.0, double.infinity);
    return Semantics(
        liveRegion: true,
        label: l.firstRunProgress(step.index + 1, 3),
        child: LayoutBuilder(builder: (context, constraints) {
          final compactLabels = constraints.maxWidth <
              300 * MediaQuery.textScalerOf(context).scale(14) / 14;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            _steps(context, labels, diameter, compactLabels),
            if (compactLabels) ...[
              const SizedBox(height: 8),
              Text(labels[step.index],
                  style: const TextStyle(color: MoshColors.fg2)),
            ],
          ]);
        }));
  }

  Widget _steps(BuildContext context, List<String> labels, double diameter,
          bool compactLabels) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0)
            Expanded(
                child: Padding(
                    padding: EdgeInsets.only(top: diameter / 2),
                    child: Divider(
                        color: index <= step.index
                            ? MoshColors.moss
                            : MoshColors.lineStrong))),
          Expanded(
              flex: 2,
              child: _item(context, labels[index], index, diameter,
                  showLabel: !compactLabels)),
        ],
      ]);

  Widget _item(BuildContext context, String label, int index, double diameter,
      {required bool showLabel}) {
    final active = index == step.index;
    final done = index < step.index;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? MoshColors.mossGlow : MoshColors.bg1,
              border: Border.all(
                  color: active || done
                      ? MoshColors.moss
                      : MoshColors.fieldBorder),
              boxShadow: active
                  ? const [
                      BoxShadow(color: MoshColors.mossGlow, blurRadius: 24)
                    ]
                  : null),
          child: done
              ? const Icon(Icons.check, size: 18, color: MoshColors.moss)
              : Text('${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium)),
      if (showLabel) ...[
        const SizedBox(height: 8),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(color: active ? MoshColors.fg1 : MoshColors.fg2)),
      ],
    ]);
  }
}

/// A stable Flex preserves form state while switching to a single column.
class SetupFrame extends StatelessWidget {
  const SetupFrame(
      {super.key,
      required this.step,
      required this.sizing,
      required this.child});
  final SetupStep step;
  final SetupSizing sizing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final devices = step == SetupStep.device;
    final stacked = sizing.stacked;
    final fit = stacked ? FlexFit.loose : FlexFit.tight;
    return Flex(
        direction: stacked ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            stacked ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
          Flexible(
              fit: fit,
              child: sizing.showIllustration
                  ? _illustration(context, stacked, devices)
                  : const SizedBox.shrink()),
          SizedBox(
              width: stacked ? 0 : sizing.columnGap,
              height:
                  stacked && sizing.showIllustration ? sizing.sectionGap : 0),
          Flexible(
              fit: fit,
              child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: child))),
        ]);
  }

  Widget _illustration(BuildContext context, bool stacked, bool devices) {
    final l = AppLocalizations.of(context)!;
    final asset = switch (step) {
      SetupStep.name => 'welcome',
      SetupStep.device => 'devices',
      SetupStep.network => 'network',
    };
    final text = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/onboarding/$asset.png',
          height: sizing.imageHeight(stacked: stacked, devices: devices),
          fit: BoxFit.contain,
          excludeFromSemantics: true),
      if (!stacked && !devices) ...[
        const SizedBox(height: 16),
        Text(step == SetupStep.name ? l.firstRunWelcome : l.firstRunAlmostReady,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(color: MoshColors.fg2)),
        const SizedBox(height: 12),
        Text(
            step == SetupStep.name
                ? l.firstRunWelcomeBody
                : l.firstRunNetworkIntro,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: MoshColors.fg2)),
        if (step == SetupStep.name) ...[
          const SizedBox(height: 24),
          const SetupPrivacyNote(),
        ],
      ],
    ]);
  }
}
