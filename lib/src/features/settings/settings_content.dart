import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/device_link/devices_settings_section.dart';

import 'about_settings_section.dart';
import 'connection_settings_section.dart';
import 'privacy_settings_section.dart';
import 'profile_settings_section.dart';
import 'settings_navigation.dart';
import 'package:mosh/src/features/shared/page_header.dart';
import 'voice_settings_section.dart';

/// One bounded scroller per section, under its page header: the page's
/// margins, 32 by 40 px on the desktop, and 24 px between header and cards.
class SettingsContent extends StatelessWidget {
  const SettingsContent(
      {super.key, required this.section, required this.wide, this.onBack});

  final SettingsSection section;
  final bool wide;

  /// The way back to the list of sections, in a narrow window.
  final VoidCallback? onBack;

  /// The widest a settings card is drawn.
  static const double maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      key: PageStorageKey(section),
      padding: wide
          ? const EdgeInsets.symmetric(
              horizontal: MoshSpace.s10, vertical: MoshSpace.s8)
          : const EdgeInsets.fromLTRB(
              MoshSpace.s4, MoshSpace.s1, MoshSpace.s4, MoshSpace.s4),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                  title: section.label(l),
                  line: section.line(l),
                  onBack: wide ? null : onBack,
                  backTooltip: l.settingsBackToSections),
              const SizedBox(height: MoshSpace.s6),
              _body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (section) {
        SettingsSection.sound => const VoiceSettingsSection(),
        SettingsSection.profile => const ProfileSettingsSection(),
        SettingsSection.devices => const DevicesSettingsSection(),
        SettingsSection.connection => const ConnectionSettingsSection(),
        SettingsSection.privacy => const PrivacySettingsSection(),
        SettingsSection.about => const AboutSettingsSection(),
      };
}
