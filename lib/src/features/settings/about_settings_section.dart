import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/distribution_channel_provider.dart';

import 'about_update_notice.dart';
import 'app_package_info_provider.dart';
import 'settings_card.dart';

/// Build identity and protection limits, rather than runtime security status.
///
/// Only a build that updates itself checks the release feed: a store build
/// shows its version and leaves updates to the store that installed it.
class AboutSettingsSection extends ConsumerWidget {
  const AboutSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final info = ref.watch(appPackageInfoProvider);
    final selfUpdates = ref.watch(distributionChannelProvider).selfUpdates;
    return SettingsSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _identity(context, l, info),
          if (selfUpdates && _hasVersion(info)) ...[
            const SizedBox(height: 12),
            const AboutUpdateNotice(),
          ],
          const SizedBox(height: 20),
          Text(l.cryptoNoticeBody, style: text.bodySmall),
          const SizedBox(height: 12),
          Text(l.settingsAboutNetworkBody, style: text.bodySmall),
        ],
      ),
    );
  }

  Widget _identity(
      BuildContext context, AppLocalizations l, AsyncValue<PackageInfo> info) {
    final text = Theme.of(context).textTheme;
    return SettingsCardHeader(
      icon: Icons.verified_user,
      title: Text('Mosh', style: text.headlineSmall),
      subtitle: Text(_version(l, info), style: text.bodySmall),
    );
  }

  /// The update notice compares against the installed version, so it waits
  /// for a successful package read instead of guessing.
  bool _hasVersion(AsyncValue<PackageInfo> info) =>
      info.value?.version.isNotEmpty ?? false;

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
