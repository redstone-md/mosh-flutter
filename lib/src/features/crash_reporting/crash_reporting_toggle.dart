/// The opt-in crash-reporting switch (ADR 0035). Its subtitle is the
/// contract: what a report carries and what it never does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/async_switch_tile.dart';

import 'crash_reporting.dart';

class CrashReportingToggle extends ConsumerWidget {
  const CrashReportingToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final reporting = ref.watch(crashReportingProvider);
    return AsyncSwitchTile(
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
