// The About settings section: the app version line and the crypto notice
// (moved from the onboarding menu's About disclosure, which the gear menu
// replaces).
library;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

class AboutSettingsSection extends StatefulWidget {
  const AboutSettingsSection({super.key});

  @override
  State<AboutSettingsSection> createState() => _AboutSettingsSectionState();
}

class _AboutSettingsSectionState extends State<AboutSettingsSection> {
  String? _version;

  @override
  void initState() {
    super.initState();
    // The build's pubspec version (the one the release tags match). Read
    // once on mount; a failure leaves the line absent, not a crash.
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Mosh',
          style: theme.textTheme.titleMedium?.copyWith(
            color: MoshColors.fg1,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_version != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            _version!,
            style: theme.textTheme.bodySmall?.copyWith(color: MoshColors.fg3),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          l.cryptoNoticeBody,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
