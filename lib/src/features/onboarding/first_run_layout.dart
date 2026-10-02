import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'first_run_profile.dart';

class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step});
  final SetupStep step;

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
                      padding: const EdgeInsets.only(top: 20),
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
          width: 40,
          height: 40,
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
      const SizedBox(height: 10),
      Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(color: active ? MoshColors.fg1 : MoshColors.fg2)),
    ]);
  }
}

/// Reference composition: two columns for name/network, centered device scene.
class SetupFrame extends StatelessWidget {
  const SetupFrame({super.key, required this.step, required this.child});
  final SetupStep step;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final centered = step == SetupStep.device;
        final illustration = _illustration(context, centered);
        if (centered || size.maxWidth < 740) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                illustration,
                const SizedBox(height: 28),
                Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: child)),
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: illustration),
          Container(
              width: 1,
              height: 440,
              margin: const EdgeInsets.symmetric(horizontal: 40),
              color: MoshColors.line),
          Expanded(child: child),
        ]);
      });

  Widget _illustration(BuildContext context, bool centered) {
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
        height: centered ? 220 : 340,
        fit: BoxFit.contain,
        excludeFromSemantics: true);
    return Column(children: [
      if (!centered) image,
      if (!centered) const SizedBox(height: 16),
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
      if (centered) const SizedBox(height: 20),
      if (centered) image,
      if (step == SetupStep.name) ...[
        const SizedBox(height: 28),
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
