import 'package:flutter/material.dart';

import 'settings_card.dart';

/// A visible opt-in with independent details and an always-visible notice.
class SettingsToggleCard extends StatelessWidget {
  const SettingsToggleCard({
    required PageStorageKey<String> key,
    required this.icon,
    required this.toggle,
    required this.detailsTitle,
    required this.details,
    this.notice,
  }) : super(key: key);

  final IconData icon;
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
            _header(context),
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

  Widget _header(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final stacked = constraints.maxWidth < 360 * textScale;
          return Flex(
            direction: stacked ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsIcon(icon),
              SizedBox(width: stacked ? 0 : 16, height: stacked ? 12 : 0),
              Flexible(
                flex: stacked ? 0 : 1,
                fit: FlexFit.tight,
                child: toggle,
              ),
            ],
          );
        },
      );

  Widget _notice(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 12),
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
