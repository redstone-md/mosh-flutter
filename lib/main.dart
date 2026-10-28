import 'dart:async' show unawaited;
import 'dart:io' show Platform;

// `hide LockState` resolves an ambiguous-import clash: material re-exports
// a `LockState` (ShortcutActivator-behavior enum) and the lock screen
// defines its own. main() only uses the MoshLockScreen one (picking
// `initialState` on a BIOMETRIC_UNAVAILABLE catch), so hiding Flutter's is
// the minimal disambiguation (vs. aliasing the lock-screen import, which
// would force `lock.LockState` at the two call sites).
import 'package:flutter/material.dart' hide LockState;
import 'package:mosh/src/features/plus/user_plus_badge.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/deeplink/mosh_deep_link.dart';
import 'package:mosh/src/deeplink/mosh_url_scheme_windows.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/features/shared/toasts/toast_host.dart';
import 'package:mosh/src/features/crash_reporting/crash_reporting.dart';
import 'package:mosh/src/features/lock/mosh_lock_screen.dart';
import 'package:mosh/src/platform/app_data_dir.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/platform/mobile_dek.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/features/onboarding/first_run_gate.dart';
import 'package:mosh/src/features/voice_call/call_window_app.dart';
import 'package:mosh/src/features/voice_call/android_pip_overlay.dart';
import 'package:mosh/src/features/voice_call/process_call_window.dart';
import 'package:mosh/src/state/locale_provider.dart';
import 'package:mosh/src/platform/native_menu_localization.dart';
import 'package:mosh/src/features/lock/mosh_lock_app.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/lock/android_app_lock_frame.dart';
import 'package:mosh/src/state/production_provider_overrides.dart';
import 'package:mosh/src/rust/frb_generated.dart'; // RustLib (init entrypoint)
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/platform/desktop_window_frame.dart';

import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/media_stream_server.dart';
import 'package:window_manager/window_manager.dart' show windowManager;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final relauncher = DesktopAppRelauncher(arguments: args);
  // Initialize window_manager before any `isFocused()` call (the
  // incoming-call focus check in VoiceCallLayer awaits it on desktop).
  // window_manager is a DESKTOP-only plugin: on Android/iOS
  // `ensureInitialized()` throws `MissingPluginException`, which as the
  // first `await` in main() killed the isolate before `runApp` and left the
  // Android launch on the native splash. Gate to the supported desktop
  // hosts; the later `isFocused()` callers are themselves desktop-gated.
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    if (args.contains(callWindowProcessArgument) || isCallWindowProcess) {
      await launchProcessCallWindow();
      return;
    }
  }
  final windowController = await DesktopWindowController.initialize();
  // Load intl date symbols once so non-en locales (e.g. ru) format dates
  // in-locale via `DateFormat` (`formatClock`/`formatClockFull`). en ships
  // loaded by default, but calling it unconditionally keeps init
  // single-path. Must run BEFORE any locale-dependent render.
  await initializeDateFormatting();
  // frb 2.x: must initialize the bridge before any api call. In test
  // environments without the native cdylib this throws; main() is only
  // exercised in real device/desktop runs, not in `flutter test`.
  await RustLib.init();
  if (Platform.isWindows || Platform.isAndroid) {
    // The owner retains the process-lifetime singleton and its observer.
    // MediaStreamLifecycleOwner.start stores the owner for this purpose.
    await MediaStreamLifecycleOwner.start();
  }
  MediaKit.ensureInitialized();
  // Register the `mosh://` custom URL scheme with Windows so the OS
  // launches mosh.exe (URI as launch arg) for a `mosh://...` link. The
  // runner already pipes launch args to Dart; this is the OS-association
  // half. Windows-only + best-effort: skipped off-Windows and on registry
  // failure (logged), so startup is never blocked. Idempotent under HKCU.
  if (Platform.isWindows) {
    registerMoshUrlScheme();
  }
  final appAccess = Platform.isAndroid ? AndroidAppAccess() : null;
  final waiting = Platform.isAndroid
      ? AndroidWaitingOwner(AndroidWaitingPlatform(), BackgroundCommands())
      : null;
  // M-5 (ADR 0010): resolve the app-private data directory ONCE via
  // `getApplicationSupportDirectory()` (path_provider) and hand it to Rust
  // via the frb `setAppDataDir` bridge call BEFORE the private-DM runtime
  // constructs (it reads the dir to open `history.redb` + the
  // AttachmentStore). Runs on ALL platforms; the bridge caches the path in
  // `app_data_dir.appDataDir()` so `mobile_dek._historyRedbPath()` reuses
  // the SAME dir -- no divergence between Dart's DB-exists check and Rust's
  // open. Must run BEFORE `initMobileDek()` and the first runtime
  // construct; idempotent-once on the Rust side.
  await setAppDataDirBridge();
  // ADR 0035: start opt-in crash reporting once the consent file is
  // readable (it lives in the data dir just bridged). Not awaited: the SDK
  // init must not hold back the first frame, so failures in the first
  // moments of launch may go unreported. A no-op without consent or without
  // a build DSN; never throws.
  final crashReporting = CrashReporting(bridge: BridgeFacade());
  unawaited(crashReporting.resume());
  // Subscribe to the `mosh://` link stream BEFORE runApp so the cold-start
  // initial link is captured (app_links delivers it just after the first
  // frame; the intake replays it once the GoRouter is mounted). Single
  // scheme (ADR 0015): non-`mosh` URIs are ignored. The intake navigates
  // to /join with the URI as `extra`, which the /join route forwards to
  // InvitePasteScreen.initialInviteUri. app_links is a no-op interface on
  // hosts without a registered implementation (e.g. `flutter test`), so
  // this stays green in tests. The handle lives for the process.
  startMoshDeepLinkIntake();
  // runApp FIRST with the splash placeholder (`_appRoot` defaults to
  // `SizedBox()`) so the first frame is NOT blocked on key loading
  // below. The Android branch later resolves `root` and flips the
  // tree via `_appRoot.value = root`; desktop/iOS flip it to `MoshApp`
  // synchronously.
  runApp(
    ProviderScope(
      overrides: [
        ...productionOverrides,
        crashReportingProvider.overrideWithValue(crashReporting),
        if (appAccess != null)
          androidAppAccessProvider.overrideWithValue(appAccess),
        if (waiting != null)
          androidWaitingOwnerProvider.overrideWithValue(waiting),
      ],
      child: ValueListenableBuilder<Widget>(
        valueListenable: _appRoot,
        builder: (BuildContext context, Widget value, _) => appAccess == null
            ? value
            : AndroidAppLockFrame(access: appAccess, child: value),
      ),
    ),
  );
  final Widget root;
  if (Platform.isAndroid) {
    root = await _androidStartupRoot(
      access: appAccess!,
      relauncher: relauncher,
      waiting: waiting!,
    );
  } else {
    root = MoshApp(relauncher: relauncher, windowController: windowController);
  }
  _appRoot.value = root;
}

/// Loads the history key without an Activity; key failures stay visible
/// without opening history.
Future<Widget> _androidStartupRoot({
  required AndroidAppAccess access,
  required DesktopAppRelauncher relauncher,
  required AndroidWaitingOwner waiting,
}) async {
  Future<void> initialize() async {
    await waiting.prepare();
    await initMobileDek();
    // Key loading never grants interactive chat access.
    await access.initialize();
    await waiting.attach();
  }

  try {
    await initialize();
    return MoshApp(relauncher: relauncher);
  } catch (_) {
    await waiting.startupFailed('keyUnavailable');
    await access.initialize();
    return MoshLockApp(
        screen: MoshLockScreen(
      retry: initialize,
      swapTo: (next) => _appRoot.value = next,
      nextApp: MoshApp(relauncher: relauncher),
      initialState: LockState.failed,
    ));
  }
}

/// The running app's root widget. Defaults to `const SizedBox()` (the
/// splash placeholder `runApp` mounts first); `main()` flips it to the
/// resolved `MoshApp` or `MoshLockScreen` AFTER `runApp` (so the first
/// frame is not blocked on key loading). The lock screen's
/// retry-success path writes the real `MoshApp` here via its `swapTo`
/// callback, under the single `ProviderScope`, without a second `runApp`.
final ValueNotifier<Widget> _appRoot = ValueNotifier<Widget>(const SizedBox());

class MoshApp extends ConsumerWidget {
  const MoshApp({super.key, this.relauncher, this.windowController});

  final DesktopWindowController? windowController;

  final DesktopAppRelauncher? relauncher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = MaterialApp.router(
      title: 'Mosh',
      debugShowCheckedModeBanner: false,
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // App dark palette, centralized in lib/src/app/mosh_theme.dart so
      // this stays a thin `MaterialApp.router` call.
      theme: moshThemeData,
      // The setup gate defers mounting routes while retaining incoming links.
      routerConfig: appRouter,
      // Ink ripples are motion: with the platform's reduce-motion setting
      // on, every InkWell below drops its splash.
      builder: (context, child) => Theme(
          data: MediaQuery.disableAnimationsOf(context)
              ? Theme.of(context)
                  .copyWith(splashFactory: NoSplash.splashFactory)
              : Theme.of(context),
          // Above the first-run gate and the call strip, so every action
          // reports through the one toast stack.
          child: AndroidPipOverlay(
            child: DesktopWindowFrame(
              controller: windowController,
              router: appRouter,
              child: ToastHost(
                child: NativeMenuLocalization(
                  child: FirstRunGate(
                    child: PlusHost(child: child ?? const SizedBox()),
                  ),
                ),
              ),
            ),
          )),
    );
    return DesktopAppRelauncherScope(
      relauncher: relauncher ?? DesktopAppRelauncher.unsupported(),
      child: app,
    );
  }
}
