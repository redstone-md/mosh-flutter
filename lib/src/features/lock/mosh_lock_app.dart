import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/lock/mosh_lock_screen.dart';
import 'package:mosh/src/state/locale_provider.dart';

/// Startup can show the lock screen before the router and setup gate mount.
/// It still needs the same saved interface language as the unlocked app.
class MoshLockApp extends ConsumerWidget {
  const MoshLockApp({super.key, required this.screen});
  final MoshLockScreen screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'Mosh',
        debugShowCheckedModeBanner: false,
        locale: ref.watch(localeProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: moshThemeData,
        home: screen,
      );
}
