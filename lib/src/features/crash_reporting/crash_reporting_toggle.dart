import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/settings/settings_toggle_card.dart';

import 'crash_reporting.dart';

class CrashReportingToggle extends ConsumerWidget {
  const CrashReportingToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final reporting = ref.watch(crashReportingProvider);
    return SettingsToggleCard(
      key: const PageStorageKey('privacy-crash-details'),
      notice: l.settingsCrashReportsNativeWarning,
      detailsTitle: l.settingsCrashReportsDetailsTitle,
      details: l.settingsCrashReportsDetails,
      icon: MoshIcons.bug,
      title: l.settingsCrashReportsTitle,
      subtitle: reporting.available
          ? l.settingsCrashReportsSubtitle
          : l.settingsCrashReportsUnavailable,
      read: reporting.isEnabled,
      write: reporting.setEnabled,
      enabled: reporting.available,
    );
  }
}
