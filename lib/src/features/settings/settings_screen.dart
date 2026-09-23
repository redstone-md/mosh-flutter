// Settings screen: a Discord-like two-pane surface — a section nav on
// the left, the active section's content on the right — reached from the
// gear at the bottom of the sessions rail.
//
// Sections live in their own files (file budget): Voice & Video (device
// pickers), Connection (the advanced controls moved out of the onboarding
// menu), About (version + crypto notice). This file owns only the frame:
// the section enum, the nav list, the content switch, and the mobile
// degradation to a single scrolling column (the shell's two-pane layout
// does not apply inside a route; the breakpoint mirrors the shell's).
//
// No section holds state beyond its own fields; navigation between
// sections is a local `_SettingsSection` + setState, not a route, so the
// browser-style back button exits the whole screen the same way Esc does.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'about_settings_section.dart';
import 'connection_settings_section.dart';
import 'voice_settings_section.dart';

/// Below this width the section nav becomes a dropdown and the content
/// pane takes the full width (mobile).
const double kSettingsTwoPaneMinWidth = 700;

/// The sections, in nav order.
enum _SettingsSection { voice, connection, about }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection _section = _SettingsSection.voice;

  String _sectionLabel(AppLocalizations l, _SettingsSection section) =>
      switch (section) {
        _SettingsSection.voice => l.settingsSectionVoice,
        _SettingsSection.connection => l.settingsSectionConnection,
        _SettingsSection.about => l.settingsSectionAbout,
      };

  Widget _sectionBody(_SettingsSection section) => switch (section) {
        _SettingsSection.voice => const VoiceSettingsSection(),
        _SettingsSection.connection => const ConnectionSettingsSection(),
        _SettingsSection.about => const AboutSettingsSection(),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final wide = MediaQuery.sizeOf(context).width >= kSettingsTwoPaneMinWidth;

    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 220,
                child: _SectionNav(
                  sections: _SettingsSection.values,
                  active: _section,
                  labelOf: (s) => _sectionLabel(l, s),
                  onPick: (s) => setState(() => _section = s),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _SectionFrame(child: _sectionBody(_section)),
                ),
              ),
            ],
          )
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<_SettingsSection>(
                    initialValue: _section,
                    items: [
                      for (final section in _SettingsSection.values)
                        DropdownMenuItem(
                          value: section,
                          child: Text(_sectionLabel(l, section)),
                        ),
                    ],
                    onChanged: (picked) {
                      if (picked != null) setState(() => _section = picked);
                    },
                  ),
                ),
                _SectionFrame(child: _sectionBody(_section)),
              ],
            ),
          );

    return Scaffold(
      backgroundColor: MoshColors.bg0,
      appBar: AppBar(
        backgroundColor: MoshColors.bg0,
        title: Text(l.settingsTitle),
        // A plain back affordance; the desktop titlebar's window controls
        // sit above the shell, not this route.
        automaticallyImplyLeading: true,
      ),
      body: wide
          ? body
          : SafeArea(
              // Mobile: keep the dropdown clear of the edge-to-edge cutout.
              child: body,
            ),
    );
  }
}

/// The nav column: one item per section, the active one carrying an
/// inset accent ring (the same shape language as the rail's active row).
class _SectionNav extends StatelessWidget {
  const _SectionNav({
    required this.sections,
    required this.active,
    required this.labelOf,
    required this.onPick,
  });

  final List<_SettingsSection> sections;
  final _SettingsSection active;
  final String Function(_SettingsSection) labelOf;
  final void Function(_SettingsSection) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: section == active ? MoshColors.bg2 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onPick(section),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    labelOf(section),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          section == active ? FontWeight.w700 : FontWeight.w500,
                      color:
                          section == active ? MoshColors.fg1 : MoshColors.fg3,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The content pane's frame: one width-bounded column so long dropdown
/// labels wrap instead of stretching the pane.
class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: child,
      ),
    );
  }
}
