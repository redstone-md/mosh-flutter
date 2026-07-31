import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/deeplink/mosh_url_scheme_windows.dart';
import 'package:mosh/src/state/locale_provider.dart';
import 'package:mosh/src/rust/frb_generated.dart'; // RustLib (init entrypoint)
import 'package:mosh/src/routing/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // frb 2.x: must initialize the bridge before any api call. In test
  // environments without the native cdylib this throws; main() is only
  // exercised in real device/desktop runs, not in `flutter test`.
  await RustLib.init();
  // S2-2: register the `mosh://` custom URL scheme with Windows so the OS
  // launches mosh.exe (URI as launch arg) for a `mosh://...` link. The
  // runner already pipes launch args to Dart; this is the OS-association
  // half. Windows-only + best-effort: skipped off-Windows and on any
  // registry failure (logged via debugPrint), so startup is never blocked.
  // Idempotent under HKCU (no admin elevation). Under `flutter test` the
  // Platform.isWindows gate skips it, keeping tests green.
  // TODO(S2-3): wire the incoming `mosh://` URI to a route via app_links'
  //   `uriLinkStream`; app_links is already a pubspec dependency but is
  //   intentionally not imported here yet (avoids an unused-import lint).
  if (Platform.isWindows) {
    registerMoshUrlScheme();
  }
  runApp(const ProviderScope(child: MoshApp()));
}

class MoshApp extends ConsumerWidget {
  const MoshApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Mosh',
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      // S2-1: route shell. Home is OnboardingScreen; tiles reach invite-paste,
      // diagnostics, and dm (via path param). The static diagnostics smoke
      // screen (MoshHome + its FutureBuilder) is gone; the bridge smoke proof
      // lives in integration_test/slice_one_test.dart and the diagnostics
      // screen. MaterialApp.router preserves title/locale/localization/theme
      // while handing navigation to appRouter.
      routerConfig: appRouter,
    );
  }
}
