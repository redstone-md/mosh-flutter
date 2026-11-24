import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/shared/mosh_disclosure.dart';

import 'settings_card.dart';

/// A Settings card whose controls are folded under a line that opens. The
/// controls mount on the first opening and keep their state when folded.
class SettingsDisclosure extends StatelessWidget {
  const SettingsDisclosure({
    required PageStorageKey<String> super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String summary;

  /// The line that opens the controls.
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => SettingsCard(
        icon: icon,
        title: title,
        hint: summary,
        child: SettingsFold(
            key: PageStorageKey(
                '${(key! as PageStorageKey<String>).value}/fold'),
            label: label,
            child: child),
      );
}

/// What a Settings card folds under its header: a divider, the line that
/// opens, and under it [child], set in to the line's own text.
class SettingsFold extends StatelessWidget {
  const SettingsFold(
      {required PageStorageKey<String> super.key,
      required this.label,
      required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: MoshSpace.s3),
          MoshDisclosure(
            key: key,
            label: label,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    MoshSpace.s3, MoshSpace.s1, MoshSpace.s3, 0),
                child: child),
          ),
        ],
      );
}
