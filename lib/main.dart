import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/locale_provider.dart';
import 'package:mosh/src/rust/frb_generated.dart'; // RustLib (init entrypoint)
import 'package:mosh/src/routing/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // frb 2.x: must initialize the bridge before any api call. In test
  // environments without the native cdylib this throws; main() is only
  // exercised in real device/desktop runs, not in `flutter test`.
  await RustLib.init();
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
