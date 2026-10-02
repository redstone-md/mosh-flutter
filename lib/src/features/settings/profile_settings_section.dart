import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/display_name_form.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';

import 'settings_card.dart';

class ProfileSettingsSection extends ConsumerWidget {
  const ProfileSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return ref.watch(firstRunProfileProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Column(children: [
            Text(l.firstRunLoadError),
            TextButton(
                onPressed: () => ref.invalidate(firstRunProfileProvider),
                child: Text(l.deviceLinkRetry)),
          ]),
          data: (profile) => SettingsCard(
              icon: Icons.person_outline,
              title: l.firstRunNameTitle,
              hint: l.firstRunNameScope,
              child: DisplayNameForm(
                  initialName: profile.displayName,
                  actionLabel: l.firstRunSaveName,
                  onSave: ref.read(firstRunProfileProvider.notifier).saveName)),
        );
  }
}
