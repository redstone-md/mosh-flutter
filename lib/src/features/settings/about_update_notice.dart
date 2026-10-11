import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/mosh_progress_bar.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_release_provider.dart';
import 'app_update_install.dart';
import 'settings_card.dart';

/// Opens a page outside the app. Injectable, so a widget test records the
/// attempt instead of calling a platform plugin.
typedef ReleasePageOpener = Future<bool> Function(Uri page);

final releasePageOpenerProvider = Provider<ReleasePageOpener>(
  (_) => (page) => launchUrl(page, mode: LaunchMode.externalApplication),
);

/// Says whether the installed build is current and, when it is not, updates it.
///
/// Mosh downloads the release artifact, checks it against the published
/// checksum and hands it to the installer, which starts the new build; the app
/// never installs anything it cannot verify. Where this host has no artifact to
/// install — Linux, or a release published without installers — the notice
/// offers the release page instead of a button that cannot finish.
class AboutUpdateNotice extends ConsumerWidget {
  const AboutUpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final candidate = ref.watch(updateCandidateProvider);
    if (candidate != null) {
      switch (ref.watch(updateInstallProvider)) {
        case UpdateInstallDownloading(:final received, :final total):
          return _downloading(context, l, received: received, total: total);
        case UpdateInstallApplying():
          return _line(context,
              icon: Icons.system_update_alt,
              tint: MoshColors.moss,
              message: l.settingsAboutUpdateApplying);
        case UpdateInstallFailed():
          return _line(context,
              icon: Icons.error_outline,
              tint: MoshColors.warn,
              message: l.settingsAboutUpdateInstallFailed,
              action: _button(
                  l.settingsAboutUpdateRetry,
                  () => ref
                      .read(updateInstallProvider.notifier)
                      .start(candidate)));
        case UpdateInstallIdle():
          break;
      }
    }
    return _feed(context, ref, l, candidate);
  }

  /// Before anything is downloaded the feed decides what the notice says.
  Widget _feed(BuildContext context, WidgetRef ref, AppLocalizations l,
          UpdateCandidate? candidate) =>
      switch (ref.watch(updateCheckProvider)) {
        AsyncData(:final value?) => _line(context,
            icon: Icons.system_update_alt,
            tint: MoshColors.moss,
            message: l.settingsAboutUpdateAvailable(value.version),
            action: _offerUpdate(context, ref, l, candidate, value)),
        AsyncData() => _line(context,
            icon: Icons.check_circle_outline,
            tint: MoshColors.moss,
            message: l.settingsAboutUpdateCurrent),
        AsyncError() => _line(context,
            icon: Icons.error_outline,
            tint: MoshColors.warn,
            message: l.settingsAboutUpdateFailed,
            action: _button(l.settingsAboutUpdateRetry,
                () => ref.invalidate(updateCheckProvider))),
        _ => _line(context,
            icon: Icons.sync,
            tint: MoshColors.fg3,
            message: l.settingsAboutUpdateChecking),
      };

  /// The artifact this host installs itself, or the release page when there is
  /// nothing to install: a button that cannot finish is worse than a link.
  Widget _offerUpdate(BuildContext context, WidgetRef ref, AppLocalizations l,
      UpdateCandidate? candidate, PublishedRelease release) {
    if (candidate == null || !ref.watch(updateApplierProvider).supported) {
      return _button(l.settingsAboutUpdateOpen,
          () => _openRelease(context, ref, l, release.pageUri));
    }
    return _button(l.settingsAboutUpdateInstall,
        () => ref.read(updateInstallProvider.notifier).start(candidate));
  }

  /// The download takes the line over: someone asked for it, so its progress is
  /// what the card is about until it finishes.
  Widget _downloading(
    BuildContext context,
    AppLocalizations l, {
    required int received,
    required int? total,
  }) {
    final fraction = total == null || total <= 0 ? null : received / total;
    final percent = ((fraction ?? 0) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _line(context,
            icon: Icons.downloading,
            tint: MoshColors.moss,
            message: fraction == null
                ? l.settingsAboutUpdateDownloadingUnknown
                : l.settingsAboutUpdateDownloading(percent)),
        const SizedBox(height: 6),
        MoshProgressBar(
            fraction: fraction,
            semanticsLabel: l.settingsAboutUpdateDownloading(percent)),
      ],
    );
  }

  /// Keeps the geometry of the settings notice rows: a 20px icon and the
  /// shared icon-to-text gap. The action takes its own line when a long word
  /// and a large text scale leave no room, rather than overflowing the card.
  Widget _line(
    BuildContext context, {
    required IconData icon,
    required Color tint,
    required String message,
    Widget? action,
  }) =>
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: SettingsCardHeader.iconTextGap,
        runSpacing: 4,
        children: [
          Icon(icon, size: 20, color: tint),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) action,
        ],
      );

  Widget _button(String label, VoidCallback onPressed) =>
      TextButton(onPressed: onPressed, child: Text(label));

  Future<void> _openRelease(
      BuildContext context, WidgetRef ref, AppLocalizations l, Uri page) async {
    final opened = await ref.read(releasePageOpenerProvider)(page);
    if (!opened && context.mounted) {
      ref
          .read(toasterProvider)
          .show(l.settingsAboutUpdateOpenFailed, kind: ToastKind.error);
    }
  }
}
