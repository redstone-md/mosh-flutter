import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';

import 'settings_navigation.dart';

/// The same keyboard-accessible section rows serve the sidebar and narrow list.
class SettingsNav extends StatelessWidget {
  const SettingsNav({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onExit,
    this.sidebar = false,
  });

  final SettingsSection? selected;
  final ValueChanged<SettingsSection> onSelect;
  final VoidCallback onExit;
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(sidebar ? 20 : 16),
      children: [
        OutlinedButton.icon(
          onPressed: onExit,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: Text(l.settingsBackToChats),
          style: OutlinedButton.styleFrom(
            alignment: AlignmentDirectional.centerStart,
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 32),
        Semantics(
          header: true,
          child: Text(l.settingsTitle,
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 16),
        for (final section in SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SectionRow(
              section: section,
              selected: sidebar && selected == section,
              showChevron: !sidebar,
              onTap: () => onSelect(section),
            ),
          ),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.selected,
    required this.showChevron,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? MoshColors.mossGlow : Colors.transparent,
        borderRadius: MoshShapes.conversationRow,
        child: InkWell(
          onTap: onTap,
          borderRadius: MoshShapes.conversationRow,
          child: FocusRing(
            radius: MoshShapes.conversationRow,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(section.icon,
                    size: 22,
                    color: selected ? MoshColors.moss : MoshColors.fg2),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(section.label(AppLocalizations.of(context)!),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          )),
                ),
                if (showChevron) const Icon(Icons.chevron_right, size: 18),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
