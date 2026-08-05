import 'dart:async' show Completer;
import 'dart:io' show Platform;

// `hide LockState` resolves an ambiguous-import clash: Flutter's
// `package:flutter/material.dart` (via `shortcuts.dart`) re-exports a
// `LockState` (a ShortcutActivator-behavior enum), and this file's lock
// screen also defines `LockState` (the MoshLockScreen visual state).
// main() only ever references the MoshLockScreen `LockState` (to pick
// `initialState` on a BIOMETRIC_UNAVAILABLE catch); it never uses
// Flutter's, so hiding Flutter's from the material import is the
// minimal disambiguation (vs. aliasing the lock-screen import, which
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
import 'package:mosh/src/state/locale_provider.dart';
import 'package:mosh/src/rust/frb_generated.dart'; // RustLib (init entrypoint)
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/routing/app_router.dart';

import 'package:mosh/src/features/vpn/vpn_consent_overlay.dart';
import 'package:window_manager/window_manager.dart' show windowManager;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final relauncher = DesktopAppRelauncher(arguments: args);
  // Slice-3 voice-call: initialize window_manager before any isFocused()
  // call (the incoming-call OS-notification focus check in VoiceCallLayer
  // awaits `windowManager.isFocused()` on Windows/macOS). Must run after
  // WidgetsFlutterBinding and before the first frame. window_manager is a
  // DESKTOP-only plugin (Windows/macOS/Linux): it registers NO platform
  // channel implementation on Android/iOS, so `ensureInitialized()` there
  // throws `MissingPluginException('ensureInitialized' on channel
  // window_manager)` -- which, as the first `await` in main(), killed the
  // isolate before `runApp` and left the Android launch showing only the
  // native splash (device-pass finding, ADR slice-3). Gate to the supported
  // desktop hosts so Android/iOS skip it (and `flutter test` already skips
  // it via no host). The later `windowManager.isFocused()` callers are
  // themselves desktop-gated, so no Android call site reaches a missing
  // channel.
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
  }
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
  // Foreground gate (ADR 0011 follow-on): construct the lifecycle gate
  // RIGHT AFTER ensureInitialized() so its WidgetsBindingObserver is
  // registered BEFORE runApp pumps the first frame -- the first
  // `AppLifecycleState.resumed` can fire asynchronously after the first
  // frame is pumped, and an observer added after that transition would
  // miss it. The gate is a local (not a global): it is only `await`ed in
  // the Android branch below, but constructing it on all platforms is
  // harmless -- on desktop/iOS the observer fires but nothing awaits
  // `waitUntilResumed()`, so the completer just completes into the void.
  // We keep it scoped to main()'s lifetime (parallel to `_appRoot`); no
  // `dispose()` is needed because the gate lives for the whole process.
  final LifecycleGate gate = LifecycleGate();
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
  // ADR 0011 follow-on: runApp FIRST with the splash placeholder
  // (`_appRoot` defaults to `SizedBox()`) so the first frame is NOT
  // blocked on the foreground-gate await below. The Android branch then
  // resolves `root` (after `waitUntilResumed()` + `initMobileDek()`) and
  // flips the tree via `_appRoot.value = root`; desktop/iOS flip it to
  // `MoshApp` synchronously. Deep-link intake was subscribed above so the
  // cold-start initial link is captured before this first frame pumps.
  runApp(
    ProviderScope(
      child: ValueListenableBuilder<Widget>(
        valueListenable: _appRoot,
        builder: (BuildContext context, Widget value, _) => value,
      ),
    ),
  );
  // M-8 (ADR 0011): run the Android DEK init behind a try/on PlatformException
  // so a biometric cancel (which makes `flutter_secure_storage`'s `read()` throw
  // a `PlatformException` from BiometricPrompt) does NOT propagate unhandled
  // out of main()'s await and crash main() (leaving the splash placeholder
  // on screen). On cancel we run a MoshLockScreen (fail-closed retry UI)
  // instead; on success we run MoshApp.
  // ONLY PlatformException is caught: a real DEK error (the fail-closed
  // StateError when a DB exists but the Keystore has no DEK, or a corrupt
  // Keystore / wrong-length DEK) still propagates -- those are NOT swallowed
  // into the lock screen; they crash main() as today (ADR 0011 fail-closed).
  // Desktop/iOS are unaffected: initMobileDek is a no-op off-Android, so the
  // try block completes synchronously and the success branch runs MoshApp.
  // Not `final`: the try/catch may assign twice if the try assigns and then
  // throws on a later statement (the analyzer treats that as a re-assignment
  // for a `final` local). A plain local is assigned exactly once per control
  // flow here, but Dart's definite-assignment rule is conservative here.
  Widget root;
  if (Platform.isAndroid) {
    // Foreground guard: do NOT touch the Android Keystore (via
    // `flutter_secure_storage`) until the app is in the foreground
    // (`AppLifecycleState.resumed`). When Android relaunches mosh in the
    // BACKGROUND on a LOCKED device, `flutter_secure_storage` 10.3.1
    // enters infinite recursion in its key-mismatch recovery path
    // (handleKeyMismatch -> migrateData -> migrateNonBiometric ->
    // onError -> deleteAllDataAndKeys -> initializeStorageCipher -> ...)
    // ending in StackOverflowError FATAL, preceded by keystore2 "device is
    // locked". That wipes the Keystore DEK and orphans `history.redb`
    // (DB exists, DEK gone -> the fail-closed StateError blocks
    // onboarding). On a normal foreground unlocked launch
    // `initializeStorageCipher` succeeds and the recursion never starts;
    // the BiometricPrompt requires a foreground activity anyway. A
    // background relaunch of a locked device never fires `resumed`, so the
    // Keystore is never called -- no StackOverflow, by design. The OS may
    // later foreground the app (fires resumed -> proceeds normally) or kill
    // the process (acceptable). This is correct gating, not a deadlock.
    // `runApp` already ran above with the splash placeholder, so this
    // await does NOT block the first frame; the gate completes
    // asynchronously and `_appRoot.value = root` below flips the tree.
    await gate.waitUntilResumed();
    try {
      await initMobileDek();
      root = MoshApp(relauncher: relauncher);
    } on PlatformException catch (error) {
      // Two failure modes collapse into this one PlatformException catch:
      // (1) a biometric CANCEL (the prompt was dismissed) -- recoverable
      // by re-prompting, so the lock screen's `canceled` state with a
      // Retry button is correct; (2) `BIOMETRIC_UNAVAILABLE` -- the device
      // has NO enrolled PIN/pattern/password/biometric, so re-prompting
      // cannot mint a Keystore key (the device itself must be secured
      // first). Distinguishing them here avoids the prior default-init
      // hang: without branching, the default `initialState`
      // (`authenticating`, the spinner shown only while a retry is in
      // flight) left the lock screen on the spinner forever -- no Retry
      // button visible, no message, indistinguishable from the native
      // splash / a hang. The message match is the only field
      // `flutter_secure_storage` surfaces for this case (verified on
      // device: `message: "BIOMETRIC_UNAVAILABLE: Biometric enforcement
      // enabled but device has no PIN, pattern, password, or biometric
      // enrolled. Cannot generate secure key."`).
      final bool insecureDevice =
          error.message?.contains('BIOMETRIC_UNAVAILABLE') ?? false;
      root = MoshLockScreen(
        swapTo: (Widget next) => _appRoot.value = next,
        nextApp: MoshApp(relauncher: relauncher),
        initialState:
            insecureDevice ? LockState.insecureDevice : LockState.canceled,
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
/// frame is not blocked on the foreground-gate await). `MoshLockScreen`'s
/// retry-success path writes the real `MoshApp` here via its `swapTo`
/// callback, flipping the tree under the single `ProviderScope` without a
/// second `runApp`. See mosh_lock_screen.dart for the rationale.
final ValueNotifier<Widget> _appRoot =
    ValueNotifier<Widget>(const SizedBox());

/// Foreground gate for the Android Keystore init (ADR 0011 follow-on).
///
/// Completes a `Future` on the first observed `AppLifecycleState.resumed`,
/// so `main()` can `await` it before touching `flutter_secure_storage`
/// (the Android Keystore). This eliminates the device-locked
/// background-relaunch recursion that wiped the DEK and orphaned
/// `history.redb`. The observer transition is the PRIMARY mechanism; the
/// constructor also does a best-effort fast path reading
/// `WidgetsBinding.instance.lifecycleState` -- but on a cold start that
/// value may be null before the first frame, so the observer's first
/// `resumed` is the relied-upon signal (warm starts where the binding
/// already reports `resumed` complete eagerly).
///
/// DESIGN: the state-transition body is extracted into the
/// `@visibleForTesting` `handleLifecycleState` method so a unit test can
/// drive it deterministically without binding-internal APIs. The gate
/// lives for the process lifetime (parallel to `_appRoot`), so it has no
/// `dispose()` -- leaving the observer attached for the whole process is
/// harmless and matches `_appRoot`'s process-lifetime scope.
class LifecycleGate with WidgetsBindingObserver {
  LifecycleGate() {
    WidgetsBinding.instance.addObserver(this);
    // Best-effort fast path: if the binding already reports `resumed`
    // (a warm start), complete eagerly. On a cold start `lifecycleState`
    // may be null before the first frame -- `null == AppLifecycleState.resumed`
    // is `false` in Dart (null-aware equality), so the fast path is skipped
    // and the observer's first `resumed` transition is the primary signal.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _resumed.complete();
    }
  }

  final Completer<void> _resumed = Completer<void>();

  /// Whether the gate has already observed a `resumed` (or completed
  /// eagerly via the fast path). `@visibleForTesting` so the unit test can
  /// assert the cold-start (incomplete) and post-resumed (complete) states
  /// synchronously, without an async completion matcher that would block
  /// on a never-completing future.
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
    final app = MaterialApp.router(
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
      builder: (context, child) =>
          VpnConsentOverlay(child: child ?? const SizedBox()),
    );
    return DesktopAppRelauncherScope(
      relauncher: relauncher ?? DesktopAppRelauncher.unsupported(),
      child: app,
    );
  }
}
