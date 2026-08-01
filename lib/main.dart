import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/deeplink/mosh_deep_link.dart';
import 'package:mosh/src/deeplink/mosh_url_scheme_windows.dart';
import 'package:mosh/src/platform/app_data_dir.dart';
import 'package:mosh/src/platform/mobile_dek.dart';
import 'package:mosh/src/state/locale_provider.dart';
import 'package:mosh/src/rust/frb_generated.dart'; // RustLib (init entrypoint)
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/routing/app_router.dart';

import 'package:mosh/src/features/vpn/vpn_consent_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load intl date symbols once so non-en locales (e.g. ru) format dates
  // in-locale via `DateFormat` (used by `formatClock` / `formatClockFull`
  // for the locale-aware message timestamp). Idempotent + cheap; en ships
  // loaded by default, so this only matters for ru -- but calling it
  // unconditionally keeps the init single-path. Must run BEFORE any
  // locale-dependent render (runApp below).
  await initializeDateFormatting();
  // frb 2.x: must initialize the bridge before any api call. In test
  // environments without the native cdylib this throws; main() is only
  // exercised in real device/desktop runs, not in `flutter test`.
  await RustLib.init();
  // Slice-3 media viewer: initialize media_kit (the Player/Video engine
  // behind MediaViewer video + audio playback) before any Player is
  // constructed. Idempotent; skipped harmlessly under `flutter test` (no
  // MediaViewer is pumped there). Must run after WidgetsFlutterBinding.
  MediaKit.ensureInitialized();
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
  // M-5 (ADR 0010): resolve the platform's app-private data directory ONCE
  // via `getApplicationSupportDirectory()` (path_provider) and hand it to
  // Rust via the frb `setAppDataDir` bridge call BEFORE the private-DM
  // runtime constructs (the runtime constructs lazily on the first api call
  // and reads the dir to open `history.redb` + the AttachmentStore). Runs on
  // ALL platforms -- path_provider works on Android/iOS/Windows/macOS/Linux,
  // and desktop getting a real app-support dir is strictly better than the
  // pre-M-5 temp fallback. The bridge ALSO caches the path in
  // `app_data_dir.appDataDir()` so `mobile_dek._historyRedbPath()` reuses the
  // SAME dir -- no divergence between Dart's DB-exists check and Rust's open.
  // Must run BEFORE `initMobileDek()` (which reads the dir) and before the
  // first private-DM runtime construct. Idempotent-once on the Rust side, so
  // this is the single caller per process.
  await setAppDataDirBridge();
  // M-3 (ADR 0011): on Android, load/mint the at-rest history DEK from the
  // Android Keystore via `flutter_secure_storage` and inject the 32 raw bytes
  // into Rust via the frb `set_history_dek` BEFORE the private-DM runtime
  // constructs. Rust's `construct_runtime` then opens the DB (now under the
  // M-5 bridged app_data_dir) with `Persistence::open_with_dek` instead of
  // the OS keychain, so the live runtime uses the Keystore DEK on a device.
  // Desktop/iOS keep the Rust desktop keychain path: initMobileDek is a
  // no-op off-Android, so startup is never blocked on desktop.
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
      theme:
          ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
     // S2-1: route shell. Home is OnboardingScreen; tiles reach invite-paste,
     // diagnostics, and dm (via path param). The static diagnostics smoke
     // screen (MoshHome + its FutureBuilder) is gone; the bridge smoke proof
     // lives in integration_test/slice_one_test.dart and the diagnostics
     // screen. MaterialApp.router preserves title/locale/localization/theme
     // while handing navigation to appRouter.
     routerConfig: appRouter,
     // Top-level VPN-bypass consent overlay: wraps every route so the one
 // question Mosh asks about the VPN can show above any screen (React
 // mounts <VpnConsentModal gateway={gateway} /> near the root of
 // private-dm-screen.tsx). The modal self-gates: it renders
 // SizedBox.shrink() when there is nothing to ask.
     builder: (context, child) => VpnConsentOverlay(child: child ?? const SizedBox()),
    );
  }
}
