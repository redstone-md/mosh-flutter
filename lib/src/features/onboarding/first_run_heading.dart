import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'first_run_profile.dart';

/// What a step of setup asks and why Mosh asks it: the single heading of the
/// step, directly above its controls.
class SetupHeading extends StatelessWidget {
  const SetupHeading({super.key, required this.step});
  final SetupStep step;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final (title, body) = switch (step) {
      SetupStep.name => (l.firstRunNameTitle, l.firstRunNameBody),
      SetupStep.device => (l.firstRunDeviceTitle, l.firstRunDeviceBody),
      SetupStep.network => (l.firstRunNetworkTitle, l.firstRunNetworkBody),
    };
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
              header: true, child: Text(title, style: text.headlineMedium)),
          const SizedBox(height: MoshSpace.s2),
          Text(body,
              style: text.bodyLarge!
                  .copyWith(color: MoshColors.of(context).onSurfaceVariant)),
        ]);
  }
}

/// The Privacy kind of the Inline note card, under the name field: a quiet
/// note on the panel level that conversations are end-to-end encrypted.
class SetupPrivacyNote extends StatelessWidget {
  const SetupPrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Container(
      padding: const EdgeInsets.all(MoshSpace.s4),
      decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius:
              const BorderRadius.all(Radius.circular(MoshRadius.medium)),
          border: Border.all(color: colors.outlineVariant)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(MoshIcons.lock, size: MoshSpace.s5, color: colors.primary),
        const SizedBox(width: MoshSpace.s3),
        Expanded(
            child: Text(AppLocalizations.of(context)!.firstRunEncryption,
                style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}
