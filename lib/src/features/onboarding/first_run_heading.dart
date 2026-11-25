import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'package:mosh/src/features/shared/mosh_notice.dart';

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
  Widget build(BuildContext context) => MoshNotice(
        inline: true,
        tone: MoshNoticeTone.secure,
        icon: MoshIcons.lock,
        detail: AppLocalizations.of(context)!.firstRunEncryption,
      );
}
