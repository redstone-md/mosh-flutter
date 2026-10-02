import 'package:flutter/material.dart';

import 'settings_card.dart';

/// Mounts controls on first expansion and preserves their state on collapse.
/// Material owns expansion, keyboard handling and accessibility semantics.
class SettingsDisclosure extends StatefulWidget {
  const SettingsDisclosure({
    required PageStorageKey<String> key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.child,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String summary;
  final Widget child;

  @override
  State<SettingsDisclosure> createState() => _SettingsDisclosureState();
}

class _SettingsDisclosureState extends State<SettingsDisclosure> {
  bool _visited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The disclosure key keeps this bool separate from the parent's offset.
    // A restored open tile must also mount its lazily created controls.
    _visited =
        _visited || PageStorage.maybeOf(context)?.readState(context) == true;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SettingsSurface(
      child: ExpansionTile(
        leading: SettingsIcon(widget.icon),
        title: Text(widget.title, style: text.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(widget.summary, style: text.bodySmall),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: const Border(),
        collapsedShape: const Border(),
        visualDensity: VisualDensity.standard,
        maintainState: true,
        onExpansionChanged: (expanded) {
          if (expanded && !_visited) setState(() => _visited = true);
        },
        children: [if (_visited) widget.child],
      ),
    );
  }
}
