import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'first_run_profile.dart';

/// The current task is the single heading, directly above its controls.
/// Centered when stacked; start-aligned atop the wide form column.
class SetupHeading extends StatelessWidget {
  const SetupHeading({super.key, required this.step, this.centered = true});
  final SetupStep step;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final title = switch (step) {
      SetupStep.name => l.firstRunNameTitle,
      SetupStep.device => l.firstRunDeviceTitle,
      SetupStep.network => l.firstRunNetworkTitle,
    };
    final body = switch (step) {
      SetupStep.name => l.firstRunNameBody,
      SetupStep.device => l.firstRunDeviceBody,
      SetupStep.network => l.firstRunNetworkBody,
    };
    final align = centered ? TextAlign.center : TextAlign.start;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Semantics(
              header: true,
              child: Text(title,
                  textAlign: align,
                  style: Theme.of(context).textTheme.headlineMedium)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: align,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: MoshColors.fg2)),
        ]);
  }
}

class SetupPrivacyNote extends StatelessWidget {
  const SetupPrivacyNote({super.key});

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_outline, size: 16, color: MoshColors.fg2),
        const SizedBox(width: 8),
        Flexible(
            child: Text(AppLocalizations.of(context)!.firstRunEncryption,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall)),
      ]);
}
