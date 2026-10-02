import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'first_run_profile.dart';
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
    return Semantics(
        liveRegion: true,
        label: l.firstRunProgress(step.index + 1, 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0)
              Expanded(
                  child: Padding(
                      padding: EdgeInsets.only(top: compact ? 16 : 20),
                      child: Divider(
                          color: index <= step.index
                              ? MoshColors.moss
                              : MoshColors.lineStrong))),
            Expanded(flex: 2, child: _item(context, labels[index], index)),
          ],
        ]));
  }

  Widget _item(BuildContext context, String label, int index) {
    final active = index == step.index;
    final done = index < step.index;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: compact ? 32 : 40,
          height: compact ? 32 : 40,
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
      const SizedBox(height: 8),
      Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(color: active ? MoshColors.fg1 : MoshColors.fg2)),
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
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final devices = step == SetupStep.device;
        final stacked =
            size.maxWidth < 740 || devices && sizing.viewport.height >= 760;
        final fit = stacked ? FlexFit.loose : FlexFit.tight;
        return Flex(
            direction: stacked ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              Flexible(
                  fit: fit,
                  child: _illustration(context, devices,
                      sizing.imageHeight(stacked: stacked, devices: devices))),
              SizedBox(
                  width: stacked ? 0 : sizing.columnGap,
                  height: stacked ? sizing.sectionGap : 0),
              Flexible(
                  fit: fit,
                  child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: child))),
            ]);
      });

  Widget _illustration(BuildContext context, bool devices, double imageHeight) {
    final l = AppLocalizations.of(context)!;
    final asset = switch (step) {
      SetupStep.name => 'welcome',
      SetupStep.device => 'devices',
      SetupStep.network => 'network',
    };
    final title = switch (step) {
      SetupStep.name => l.firstRunWelcome,
      SetupStep.device => l.firstRunDeviceTitle,
      SetupStep.network => l.firstRunAlmostReady,
    };
    final body = switch (step) {
      SetupStep.name => l.firstRunWelcomeBody,
      SetupStep.device => l.firstRunDeviceBody,
      SetupStep.network => l.firstRunNetworkIntro,
    };
    final text = Theme.of(context).textTheme;
    final image = Image.asset('assets/onboarding/$asset.png',
        height: imageHeight, fit: BoxFit.contain, excludeFromSemantics: true);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!devices) image,
      if (!devices) const SizedBox(height: 16),
      Semantics(
          header: true,
          child: Text(title,
              textAlign: TextAlign.center, style: text.headlineMedium)),
      const SizedBox(height: 12),
      ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(body,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: MoshColors.fg2))),
      if (devices) const SizedBox(height: 16),
      if (devices) image,
      if (step == SetupStep.name) ...[
        SizedBox(height: sizing.compact ? 20 : 28),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline, size: 18, color: MoshColors.moss),
          const SizedBox(width: 8),
          Flexible(
              child: Text(l.firstRunEncryption,
                  textAlign: TextAlign.center, style: text.bodySmall)),
        ]),
      ],
    ]);
  }
}
