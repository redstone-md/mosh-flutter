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

/// One bounded scroller per section, under its page header. The page's
/// margins are 32 px above and below and 40 px at the sides on the desktop,
/// and 4 px above and 16 px at the sides and the foot on a phone; header and
/// cards stand 24 px apart on both.
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
