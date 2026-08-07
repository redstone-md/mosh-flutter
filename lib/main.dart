import 'dart:async' show Completer;
import 'dart:io' show Platform;

// `hide LockState` resolves an ambiguous-import clash: material re-exports
// a `LockState` (ShortcutActivator-behavior enum) and the lock screen
// defines its own. main() only uses the MoshLockScreen one (picking
// `initialState` on a BIOMETRIC_UNAVAILABLE catch), so hiding Flutter's is
// the minimal disambiguation (vs. aliasing the lock-screen import, which
// would force `lock.LockState` at the two call sites).
import 'package:flutter/material.dart' hide LockState;
import 'package:flutter/services.dart' show PlatformException;

import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/deeplink/mosh_deep_link.dart';
import 'package:mosh/src/deeplink/mosh_url_scheme_windows.dart';
import 'package:mosh/src/features/lock/mosh_lock_screen.dart';
import 'package:mosh/src/platform/app_data_dir.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/platform/mobile_dek.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/locale_provider.dart';
import 'package:mosh/src/state/production_provider_overrides.dart';
import 'package:mosh/src/rust/frb_generated.dart'; // RustLib (init entrypoint)
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/routing/app_router.dart';

import 'package:mosh/src/features/vpn/vpn_consent_overlay.dart';
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
  }
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
  // Slice-3 media viewer: initialize media_kit (the Player/Video engine
  // behind MediaViewer video + audio playback) before any Player is
  // constructed. Idempotent; skipped harmlessly under `flutter test` (no
  // MediaViewer is pumped there). Must run after WidgetsFlutterBinding.
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
  // M-3 (ADR 0011): on Android, load/mint the at-rest history DEK from the
  // Keystore via `flutter_secure_storage` and inject the 32 raw bytes into
  // Rust via the frb `set_history_dek` BEFORE the runtime constructs
  // (`Persistence::open_with_dek` instead of the OS keychain). Desktop/iOS
  // keep the Rust desktop keychain path: initMobileDek is a no-op
  // off-Android, so startup is never blocked on desktop.
  //
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
      overrides: productionOverrides,
      child: ValueListenableBuilder<Widget>(
        valueListenable: _appRoot,
        builder: (BuildContext context, Widget value, _) => value,
      ),
    ),
  );
  // M-8 (ADR 0011): run the Android DEK init behind try/on PlatformException
  // so a biometric cancel (which makes `flutter_secure_storage`'s `read()`
  // throw from BiometricPrompt) does NOT crash main() and leave the splash
  // placeholder on screen. On cancel we run a MoshLockScreen (fail-closed
  // retry UI) instead; on success, MoshApp. ONLY PlatformException is
  // caught: a real DEK error (the fail-closed StateError when the Keystore
  // has no DEK, corrupt Keystore / wrong-length DEK) still propagates and
  // crashes main() as today (ADR 0011 fail-closed). Desktop/iOS are
  // unaffected -- initMobileDek is a no-op off-Android. Not `final`: the
  // analyzer's definite-assignment rule is conservative about the try/catch
  // re-assigning `root`.
  Widget root;
  if (Platform.isAndroid) {
    // Foreground guard: do NOT touch the Android Keystore (via
    // `flutter_secure_storage`) until the app is foreground
    // (`AppLifecycleState.resumed`). When Android relaunches mosh in the
    // BACKGROUND on a LOCKED device, `flutter_secure_storage` 10.3.1
    // enters infinite recursion in its key-mismatch recovery path
    // (handleKeyMismatch -> ... -> initializeStorageCipher), ending in
    // StackOverflowError FATAL, which wipes the Keystore DEK and orphans
    // `history.redb` (DB exists, DEK gone -> the fail-closed StateError
    // blocks onboarding). On a normal foreground launch
    // `initializeStorageCipher` succeeds and the recursion never starts; a
    // locked-device background relaunch never fires `resumed`, so the
    // Keystore is never called -- no StackOverflow, by design. `runApp`
    // already ran above with the splash placeholder, so this await does
    // NOT block the first frame.
    await gate.waitUntilResumed();
    try {
      await initMobileDek();
      root = MoshApp(relauncher: relauncher);
    } on PlatformException catch (error) {
      // Two failure modes collapse into this one PlatformException catch:
      // (1) a biometric CANCEL (prompt dismissed) -- recoverable by
      // re-prompting, so the lock screen's `canceled` state with a Retry
      // button is correct; (2) `BIOMETRIC_UNAVAILABLE` -- the device has
      // NO enrolled PIN/pattern/password/biometric, so re-prompting cannot
      // mint a Keystore key. Distinguishing them avoids the prior hang:
      // without branching, the default `initialState` (`authenticating`,
      // the spinner shown only while a retry is in flight) left the lock
      // screen on the spinner forever -- no Retry button, no message. The
      // message match is the only field `flutter_secure_storage` surfaces
      // for this case (verified on device).
      final bool insecureDevice =
          error.message?.contains('BIOMETRIC_UNAVAILABLE') ?? false;
      root = MoshLockScreen(
        swapTo: (Widget next) => _appRoot.value = next,
        nextApp: MoshApp(relauncher: relauncher),
        initialState: insecureDevice
            ? LockState.insecureDevice
            : LockState.canceled,
      );
    }
  } else {
    root = MoshApp(relauncher: relauncher);
  }
  _appRoot.value = root;
}

/// The running app's root widget. Defaults to `const SizedBox()` (the
/// splash placeholder `runApp` mounts first); `main()` flips it to the
/// resolved `MoshApp` or `MoshLockScreen` AFTER `runApp` (so the first
/// frame is not blocked on the foreground-gate await). The lock screen's
/// retry-success path writes the real `MoshApp` here via its `swapTo`
/// callback, under the single `ProviderScope`, without a second `runApp`.
final ValueNotifier<Widget> _appRoot = ValueNotifier<Widget>(const SizedBox());

/// Foreground gate for the Android Keystore init (ADR 0011 follow-on).
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
  const MoshApp({super.key, this.relauncher});

  final DesktopAppRelauncher? relauncher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start the app-wide auto-poll loop (React AUTO_POLL_MS). Mounted at the
    // root, not in the shell, so a session created during onboarding starts
    // draining its inbound queue immediately -- the MLS handshake only
    // advances while something polls.
    ref.watch(autoPollProvider);
    final app = MaterialApp.router(
      title: 'Mosh',
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // 1:1 React dark palette (mosh/src/shared/styles/theme.css `:root`),
      // centralized in lib/src/app/mosh_theme.dart so this stays a thin
      // `MaterialApp.router` call.
      theme: moshThemeData,
      // Route shell: home is OnboardingScreen; tiles reach invite-paste,
      // diagnostics, and dm (via path param). MaterialApp.router hands
      // navigation to appRouter.
      routerConfig: appRouter,
      // Top-level VPN-bypass consent overlay: wraps every route so the one
      // question Mosh asks about the VPN can show above any screen (React
      // mounts <VpnConsentModal gateway={gateway} /> near the root of
      // private-dm-screen.tsx). The modal self-gates to SizedBox.shrink()
      // when there is nothing to ask.
      builder: (context, child) =>
          VpnConsentOverlay(child: child ?? const SizedBox()),
    );
    return DesktopAppRelauncherScope(
      relauncher: relauncher ?? DesktopAppRelauncher.unsupported(),
      child: app,
    );
  }
}
