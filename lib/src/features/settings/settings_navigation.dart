import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';

enum SettingsSection {
  sound(MoshIcons.mic),
  profile(MoshIcons.person),
  devices(MoshIcons.devices),
  connection(MoshIcons.link),
  privacy(MoshIcons.lock),
  about(MoshIcons.info);

  const SettingsSection(this.icon);
  final IconData icon;

  String label(AppLocalizations l) => switch (this) {
        sound => l.settingsSectionVoice,
        profile => l.settingsSectionProfile,
        devices => l.settingsSectionDevices,
        connection => l.settingsSectionConnection,
        privacy => l.settingsSectionPrivacy,
        about => l.settingsSectionAbout,
      };

  /// What the page's header says about the whole section, where it has
  /// something to say.
  String? line(AppLocalizations l) => switch (this) {
        sound => l.settingsAudioAppliesAutomatically,
        profile || devices || connection || privacy || about => null,
      };
}

/// Application-launch memory; null starts narrow windows at the section list.
/// Detail/list visibility belongs to the screen, never to this provider.
final settingsSectionProvider =
    NotifierProvider<SettingsSectionNotifier, SettingsSection?>(
        SettingsSectionNotifier.new);

class SettingsSectionNotifier extends Notifier<SettingsSection?> {
  @override
  SettingsSection? build() => null;

  void select(SettingsSection section) => state = section;

  void rememberDefault() {
    if (ref.mounted && state == null) state = SettingsSection.sound;
  }
}
