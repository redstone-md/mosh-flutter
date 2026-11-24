import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'settings_card.dart';
import 'settings_disclosure.dart';

/// The Switch kind of the Settings card: an opt-in in the card's header,
/// what explains it folded under a line that opens, and a [notice] that
/// stays in view.
class SettingsToggleCard extends StatelessWidget {
  const SettingsToggleCard({
    required PageStorageKey<String> super.key,
    required this.toggle,
    required this.detailsTitle,
    required this.details,
    this.notice,
  });

  /// The header with the switch, an `AsyncSwitchTile`.
  final Widget toggle;
  final String detailsTitle;
  final String details;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall;
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toggle,
          if (notice case final words?) ...[
            const SizedBox(height: MoshSpace.s3),
            Row(children: [
              Icon(MoshIcons.info,
                  size: MoshSpace.s5,
                  color: MoshColors.of(context).onSurfaceVariant),
              const SizedBox(width: MoshSpace.s3),
              Expanded(child: Text(words, style: text)),
            ]),
          ],
          const SizedBox(height: MoshSpace.s3),
          SettingsFold(
              key: key! as PageStorageKey<String>,
              label: detailsTitle,
              child: Text(details, style: text)),
        ],
      ),
    );
  }
}
