import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'settings_card_header.dart';
export 'settings_card_header.dart' show SettingsCardHeader, SettingsIcon;

/// The Settings card: one subject to a card. The header names the subject
/// and [child] is what the card holds under it.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCardHeader(icon: icon, title: title, subtitle: hint),
          const SizedBox(height: MoshSpace.s3),
          child,
        ],
      ),
    );
  }
}

/// A panel drawn as a card inside the background: the panel's tone with a
/// quiet edge and the card's padding, 20 px on the desktop and 16 px on a
/// phone. The edge is drawn inside the padding and takes no room of its own.
/// Cards of one page stand [gap] apart.
class SettingsSurface extends StatelessWidget {
  const SettingsSurface({super.key, required this.child});

  final Widget child;

  static const radius =
      BorderRadius.all(Radius.circular(MoshRadius.extraLarge));

  /// The room between two cards of a page.
  static const double gap = MoshSpace.s3;

  /// The card's padding on the device of [context].
  static double inset(BuildContext context) =>
      MoshControl.touch(Theme.of(context).platform)
          ? MoshSpace.s4
          : MoshSpace.s5;

  @override
  Widget build(BuildContext context) {
    final card = MoshLevel.card(MoshColors.of(context), radius);
    return Material(
      color: card.color,
      shape: card.shape,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(inset(context)), child: child),
    );
  }
}
