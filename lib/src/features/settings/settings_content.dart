import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/crash_reporting/crash_reporting_toggle.dart';
import 'package:mosh/src/features/device_link/devices_settings_section.dart';
import 'package:mosh/src/features/shared/read_receipts_toggle.dart';

import 'about_settings_section.dart';
import 'connection_settings_section.dart';
import 'settings_navigation.dart';
import 'voice_settings_section.dart';

/// One bounded scroller per section, including its heading.
class SettingsContent extends StatelessWidget {
  const SettingsContent({super.key, required this.section, required this.wide});

  final SettingsSection section;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      key: PageStorageKey(section),
      padding: EdgeInsets.symmetric(
          horizontal: wide ? 40 : 16, vertical: wide ? 40 : 24),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) ...[
                Text(l.settingsTitle, style: text.bodySmall),
                const SizedBox(height: 8),
              ],
              Semantics(
                header: true,
                child: Text(section.label(l), style: text.headlineMedium),
              ),
              const SizedBox(height: 28),
              _body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (section) {
        SettingsSection.sound => const VoiceSettingsSection(),
        SettingsSection.devices => const DevicesSettingsSection(),
        SettingsSection.connection => const ConnectionSettingsSection(),
        SettingsSection.privacy => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CrashReportingToggle(),
              SizedBox(height: 16),
              ReadReceiptsToggle(),
            ],
          ),
        SettingsSection.about => const AboutSettingsSection(),
      };
}
