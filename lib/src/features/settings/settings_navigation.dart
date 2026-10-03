import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';

enum SettingsSection {
  sound(Icons.mic_none_outlined),
  profile(Icons.person_outline),
  devices(Icons.devices_outlined),
  connection(Icons.link_outlined),
  privacy(Icons.lock_outline),
  about(Icons.info_outline);

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
}
