import 'dart:async' show Completer, unawaited;
import 'dart:io' show Platform;

// `hide LockState` resolves an ambiguous-import clash: material re-exports
// a `LockState` (ShortcutActivator-behavior enum) and the lock screen
// defines its own. main() only uses the MoshLockScreen one (picking
// `initialState` on a BIOMETRIC_UNAVAILABLE catch), so hiding Flutter's is
// the minimal disambiguation (vs. aliasing the lock-screen import, which
// would force `lock.LockState` at the two call sites).
import 'package:flutter/material.dart' hide LockState;
import 'package:mosh/src/features/plus/user_plus_badge.dart';
import 'package:flutter/services.dart' show PlatformException;

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
  // Foreground gate (ADR 0011 follow-on): construct it RIGHT AFTER
  // ensureInitialized() so its WidgetsBindingObserver is registered BEFORE
  // runApp pumps the first frame -- an observer added after the first
  // `resumed` transition would miss it. Constructed on all platforms
  // (harmless: on desktop/iOS nothing awaits `waitUntilResumed()`); only
  // the Android branch awaits it. No `dispose()` -- it lives for the
  // process (parallel to `_appRoot`).
  final LifecycleGate gate = LifecycleGate();
  final appAccess = Platform.isAndroid ? AndroidAppAccess() : null;
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
  // Load the native background DEK or migrate the original wrapping before
  // constructing history. Only missing wrapping waits for a resumed Activity.
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
  // `SizedBox()`) so the first frame is NOT blocked on the foreground-gate
  // await below. The Android branch later resolves `root` and flips the
  // tree via `_appRoot.value = root`; desktop/iOS flip it to `MoshApp`
  // synchronously.
  runApp(
    ProviderScope(
      overrides: [
        ...productionOverrides,
        crashReportingProvider.overrideWithValue(crashReporting),
        if (appAccess != null)
          androidAppAccessProvider.overrideWithValue(appAccess),
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
      gate: gate,
      relauncher: relauncher,
    );
  } else {
    root = MoshApp(relauncher: relauncher, windowController: windowController);
  }
  _appRoot.value = root;
}

/// Background wrapping loads before any foreground wait. Only an absent wrapping
/// enters legacy migration; key failures stay visible without opening history.
Future<Widget> _androidStartupRoot({
  required AndroidAppAccess access,
  required LifecycleGate gate,
  required DesktopAppRelauncher relauncher,
}) async {
  Future<void> initialize({bool repair = false}) async {
    if (repair) {
      await recoverMobileDek();
    } else {
      await initMobileDek(waitForForeground: gate.waitUntilResumed);
    }
    // Key loading/migration/repair never grants interactive chat access.
    await access.initialize();
  }

  try {
    await initialize();
    return MoshApp(relauncher: relauncher);
  } catch (error) {
    await access.initialize();
    final platform = error is PlatformException ? error : null;
    final repair = const {
      'DEK_KEY_MISSING',
      'DEK_KEY_INVALID',
      'DEK_ENVELOPE_INVALID',
    }.contains(platform?.code);
    final insecure =
        platform?.message?.contains('BIOMETRIC_UNAVAILABLE') ?? false;
    return MoshLockApp(
        screen: MoshLockScreen(
      retry: () => initialize(repair: repair),
      swapTo: (next) => _appRoot.value = next,
      nextApp: MoshApp(relauncher: relauncher),
      initialState: insecure
          ? LockState.insecureDevice
          : platform?.code == 'DEK_FOREGROUND_REQUIRED'
              ? LockState.canceled
              : LockState.failed,
    ));
  }
}

/// The running app's root widget. Defaults to `const SizedBox()` (the
/// splash placeholder `runApp` mounts first); `main()` flips it to the
/// resolved `MoshApp` or `MoshLockScreen` AFTER `runApp` (so the first
/// frame is not blocked on the foreground-gate await). The lock screen's
/// retry-success path writes the real `MoshApp` here via its `swapTo`
/// callback, under the single `ProviderScope`, without a second `runApp`.
final ValueNotifier<Widget> _appRoot = ValueNotifier<Widget>(const SizedBox());

/// Foreground gate for the retained legacy reader during Android DEK migration.
///
/// Completes a `Future` on the first observed `AppLifecycleState.resumed`,
/// so `main()` can `await` it before touching `flutter_secure_storage` —
/// eliminating the device-locked background-relaunch recursion that wiped
/// the DEK and orphaned `history.redb`. The observer transition is the
/// PRIMARY mechanism; the constructor also does a best-effort fast path
/// reading `WidgetsBinding.instance.lifecycleState`, but on a cold start
/// that may be null before the first frame, so the observer's first
/// `resumed` is the relied-upon signal (warm starts complete eagerly).
///
/// DESIGN: the transition body is extracted into the `@visibleForTesting`
/// `handleLifecycleState` method so a unit test can drive it without
/// binding-internal APIs. The gate lives for the process (parallel to
/// `_appRoot`), so it has no `dispose()`.
class LifecycleGate with WidgetsBindingObserver {
  LifecycleGate() {
    WidgetsBinding.instance.addObserver(this);
    // Best-effort fast path: if the binding already reports `resumed` (a warm
    // start), complete eagerly. On a cold start `lifecycleState` may be
    // null before the first frame, so the observer's first transition is
    // the primary signal.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _resumed.complete();
    }
  }

  final Completer<void> _resumed = Completer<void>();

  /// Whether the gate has already observed a `resumed` (or completed
  /// eagerly via the fast path). `@visibleForTesting` so the unit test can
  /// assert the cold-start / post-resumed states synchronously without
  /// awaiting a possibly never-completing future.
  @visibleForTesting
  bool get isCompleted => _resumed.isCompleted;

  /// Waits until the app has observed at least one
  /// `AppLifecycleState.resumed` (or was already `resumed` at construction
  /// via the fast path).
  Future<void> waitUntilResumed() => _resumed.future;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleState(state);
  }

  /// The state-transition body, extracted for deterministic unit testing
  /// (drives the same completer the observer uses). `@visibleForTesting` so
  /// it stays a stable test seam without exposing the gate's internals.
  @visibleForTesting
  void handleLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_resumed.isCompleted) {
      _resumed.complete();
    }
  }
}

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
