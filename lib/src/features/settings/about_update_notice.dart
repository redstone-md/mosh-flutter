import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_release_provider.dart';
import 'settings_card.dart';

/// Opens a page outside the app. Injectable, so a widget test records the
/// attempt instead of calling a platform plugin.
typedef ReleasePageOpener = Future<bool> Function(Uri page);

final releasePageOpenerProvider = Provider<ReleasePageOpener>(
  (_) => (page) => launchUrl(page, mode: LaunchMode.externalApplication),
);

/// Says whether the installed build is current and, when it is not, hands over
/// the release page.
///
/// Mosh installs nothing itself: the artifacts are unsigned, so downloading
/// stays with the platform's own flow (ADR 0045). The check runs while this
/// widget is mounted, which is the About card and nothing else.
class AboutUpdateNotice extends ConsumerWidget {
  const AboutUpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return switch (ref.watch(updateCheckProvider)) {
      AsyncData(:final value?) => _line(
          context,
          icon: Icons.system_update_alt,
          tint: MoshColors.moss,
          message: l.settingsAboutUpdateAvailable(value.version),
          action: TextButton(
            onPressed: () => _openRelease(context, ref, l, value.pageUri),
            child: Text(l.settingsAboutUpdateOpen),
          ),
        ),
      AsyncData() => _line(
          context,
          icon: Icons.check_circle_outline,
          tint: MoshColors.moss,
          message: l.settingsAboutUpdateCurrent,
        ),
      AsyncError() => _line(
          context,
          icon: Icons.error_outline,
          tint: MoshColors.warn,
          message: l.settingsAboutUpdateFailed,
          action: TextButton(
            onPressed: () => ref.invalidate(updateCheckProvider),
            child: Text(l.settingsAboutUpdateRetry),
          ),
        ),
      _ => _line(
          context,
          icon: Icons.sync,
          tint: MoshColors.fg3,
          message: l.settingsAboutUpdateChecking,
        ),
    };
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
