import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'settings_card_header.dart';
export 'settings_card_header.dart' show SettingsCardHeader, SettingsIcon;

/// The Settings card: one subject to a card. The header names the subject
/// and holds the control that matters most in [trailing]; [child] is what
/// the card holds under it.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String hint;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCardHeader(
              icon: icon, title: title, subtitle: hint, trailing: trailing),
          const SizedBox(height: MoshSpace.s3),
          child,
        ],
      ),
    );
  }
}

/// A panel drawn as a card inside the background: the panel's tone with a
/// quiet edge and the card's padding, 20 px on the desktop and 16 px on a
/// phone.
class SettingsSurface extends StatelessWidget {
  const SettingsSurface({super.key, required this.child});

  final Widget child;

  static const radius =
      BorderRadius.all(Radius.circular(MoshRadius.extraLarge));

  /// The card's padding on the device of [context].
  static double inset(BuildContext context) =>
      MoshControl.touch(Theme.of(context).platform)
          ? MoshSpace.s4
          : MoshSpace.s5;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: radius, side: BorderSide(color: colors.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(inset(context)), child: child),
    );
  }
}
