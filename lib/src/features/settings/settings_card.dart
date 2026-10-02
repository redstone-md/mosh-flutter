import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import 'settings_card_header.dart';
export 'settings_card_header.dart' show SettingsCardHeader, SettingsIcon;

/// A setting and its explanation share a surface; controls keep theme geometry.
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCardHeader(
            icon: icon,
            title: Semantics(
              header: true,
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            subtitle: Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Shared card material keeps ink, borders and clipping consistent.
class SettingsSurface extends StatelessWidget {
  const SettingsSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
        color: MoshColors.bg1,
        shape: const RoundedRectangleBorder(
            borderRadius: MoshShapes.composer,
            side: BorderSide(color: MoshColors.line)),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}
