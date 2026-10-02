import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mosh/l10n/app_localizations.dart';

import 'app_package_info_provider.dart';
import 'settings_card.dart';

/// Build identity and protection limits, rather than runtime security status.
class AboutSettingsSection extends ConsumerWidget {
  const AboutSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final info = ref.watch(appPackageInfoProvider);
    return SettingsSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _identity(context, l, info),
          const SizedBox(height: 20),
          Text(l.cryptoNoticeBody, style: text.bodySmall),
          const SizedBox(height: 8),
          ExpansionTile(
            key: const PageStorageKey('about-protection-details'),
            title: Text(l.settingsAboutProtectionDetailsTitle,
                style: text.bodySmall),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            minTileHeight: 44,
            visualDensity: VisualDensity.standard,
            shape: const Border(),
            collapsedShape: const Border(),
            children: [
              Text(l.settingsAboutProtectionDetails, style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _identity(
      BuildContext context, AppLocalizations l, AsyncValue<PackageInfo> info) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsIcon(Icons.verified_user),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mosh', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(_version(l, info), style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  String _version(AppLocalizations l, AsyncValue<PackageInfo> info) =>
      info.when(
        data: (package) => package.version.isEmpty
            ? l.settingsAboutVersionUnavailable
            : package.buildNumber.isEmpty
                ? l.settingsAboutVersion(package.version)
                : l.settingsAboutVersionBuild(
                    package.version, package.buildNumber),
        loading: () => l.settingsAboutVersionLoading,
        error: (error, stack) => l.settingsAboutVersionUnavailable,
      );
}
