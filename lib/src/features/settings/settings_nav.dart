import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';

import 'settings_navigation.dart';
import 'package:mosh/src/features/shared/page_header.dart';

/// The Settings navigation card: the sections of settings. On the desktop it
/// is the side list, with the way back to the chats it stands in for; in a
/// narrow window it is the whole first screen under its page header.
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

  /// Width of the desktop's side list: a 232 px row and the list's padding.
  static const double sidebarWidth = 248;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListView(
      padding: sidebar
          ? const EdgeInsets.symmetric(
              horizontal: MoshSpace.s2, vertical: MoshSpace.s4)
          : const EdgeInsets.fromLTRB(
              MoshSpace.s4, MoshSpace.s1, MoshSpace.s4, MoshSpace.s4),
      children: [
        if (sidebar) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onExit,
              icon: const Icon(MoshIcons.back),
              label: Text(l.settingsBackToChats),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                MoshSpace.s4, MoshSpace.s4, MoshSpace.s4, MoshSpace.s2),
            child: Semantics(
              header: true,
              child: Text(l.settingsTitle,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
        ] else
          PageHeader(
              title: l.settingsTitle,
              onBack: onExit,
              backTooltip: l.settingsBackToChats),
        for (final section in SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(top: MoshSpace.s1),
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

/// The Navigation row card: a pill as tall as a control. The selected one is
/// lit; in a narrow window a row opens a screen of its own and says so with
/// a chevron.
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
    final colors = MoshColors.of(context);
    final ink = selected ? colors.onSecondaryContainer : colors.onSurface;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        shape: MoshShapes.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: MoshShapes.pill,
          overlayColor: MoshState.layer(colors.onSurface),
          child: FocusRing(
            radius: const BorderRadius.all(Radius.circular(MoshRadius.full)),
            child: Container(
              constraints: BoxConstraints(
                  minHeight: MoshControl.height(Theme.of(context).platform)),
              padding: const EdgeInsetsDirectional.only(
                  start: MoshSpace.s4, end: MoshSpace.s3),
              child: Row(children: [
                Icon(section.icon,
                    size: MoshSpace.s5,
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant),
                const SizedBox(width: MoshSpace.s3),
                Expanded(
                  child: Text(section.label(AppLocalizations.of(context)!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge!
                          .copyWith(color: ink)),
                ),
                if (showChevron)
                  Icon(MoshIcons.chevronRight,
                      size: MoshSpace.s4, color: colors.onSurfaceMuted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
