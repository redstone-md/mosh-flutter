import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/deeplink/mosh_deep_link.dart';
import 'package:mosh/src/deeplink/mosh_url_scheme_windows.dart';
import 'package:mosh/src/platform/mobile_dek.dart';
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
  if (Platform.isWindows) {
    registerMoshUrlScheme();
  }
  // M-3 (ADR 0011): on Android, load/mint the at-rest history DEK from the
  // Android Keystore via `flutter_secure_storage` and inject the 32 raw bytes
  // into Rust via the new frb `set_history_dek` BEFORE the private-DM runtime
  // constructs (the runtime constructs lazily on the first api call). Rust's
  // `construct_runtime` then opens the DB with `Persistence::open_with_dek`
  // instead of the OS keychain, so the live runtime uses the Keystore DEK on
  // a device. Desktop/iOS keep the Rust desktop keychain path: initMobileDek
  // is a no-op off-Android, so startup is never blocked on desktop. The DB
  // path currently mirrors Rust's temp-dir fallback; TODO(ADR 0010) route a
  // real app_data_dir through the bridge so both sides agree on the path.
  if (Platform.isAndroid) {
    await initMobileDek();
  }
  // S2-3: subscribe to the `mosh://` link stream BEFORE runApp so the
  // cold-start initial link is captured (app_links delivers it shortly
  // after the first frame; the intake replays it once the GoRouter is
  // mounted). Single scheme (ADR 0015): non-`mosh` URIs are ignored. The
  // intake navigates appRouter to /join with the URI as `extra`, which the
  // /join route builder forwards to InvitePasteScreen.initialInviteUri.
  // Platform-agnostic subscription: app_links is a no-op platform interface
  // on hosts without a registered implementation (e.g. the `flutter test`
  // host), so this stays green in tests. The handle lives for the process.
  startMoshDeepLinkIntake();
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
