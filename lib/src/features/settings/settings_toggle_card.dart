import 'package:flutter/material.dart';

import 'settings_card.dart';

/// A visible opt-in with independent details and an always-visible notice.
class SettingsToggleCard extends StatelessWidget {
  const SettingsToggleCard({
    required PageStorageKey<String> key,
    required this.toggle,
    required this.detailsTitle,
    required this.details,
    this.notice,
  }) : super(key: key);

  final Widget toggle;
  final String detailsTitle;
  final String details;
  final String? notice;

  @override
  Widget build(BuildContext context) => SettingsSurface(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTileTheme(
              data: SettingsCardHeader.layout(context),
              child: toggle,
            ),
            if (notice != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _notice(context),
            ],
            const SizedBox(height: 8),
            _details(context),
          ],
        ),
      );

  Widget _notice(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: SettingsCardHeader.iconTextGap),
          Expanded(
              child:
                  Text(notice!, style: Theme.of(context).textTheme.bodySmall)),
        ],
      );

  Widget _details(BuildContext context) => ExpansionTile(
        title: Text(detailsTitle, style: Theme.of(context).textTheme.bodySmall),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        minTileHeight: 44,
        visualDensity: VisualDensity.standard,
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          Text(details, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
