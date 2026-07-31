// S2-3: Dart-side intake for the `mosh://` deep link. This is the half of
// the deep-link pipeline that lives in Dart; the other half is the Windows
// runner (windows/runner/main.cpp), which calls SendAppLinkToInstance()
// so a `mosh://` click that launches a SECOND process forwards its URI to
// the already-running instance instead of opening a second window. This
// module subscribes to that single running instance's link stream.
//
// Pipeline (single scheme, ADR 0015):
//   OS launches mosh.exe "mosh://invite?..."
//     -> runner: SendAppLinkToInstance() forwards to existing instance
//        (or, on cold start, this instance keeps the arg)
//     -> app_links Windows plugin parses argv[1], stores initialLink_
//     -> Dart: AppLinks().uriLinkStream emits the Uri (initial + later)
//     -> here: gate scheme == 'mosh', appRouter.go('/join', extra: <uri>)
//     -> /join route builder reads `extra` and seeds InvitePasteScreen
//
// State hygiene (no server/client-state split needed): the subscription is
// pure fire-and-navigate. We hold NO app data here; the only module state is
// the StreamSubscription + a tiny cold-start replay buffer. No Zustand-style
// store and no TanStack-style cache apply (this is Flutter, and app_links +
// go_router already own their respective states orthogonally).
//
// Cold-start timing (verified against app_links 7.2.1 Windows plugin,
// app_links_plugin.cpp OnListen): the initial link is emitted through the
// event channel ONLY when Dart subscribes (listen -> OnListen -> Success).
// That emission is asynchronous across the platform channel, so it lands
// AFTER runApp has built the first frame and the GoRouter is mounted. We
// still defend against the narrow race where the link arrives before the
// router has a navigator: a one-shot post-frame callback replays a pending
// link. Calling appRouter.go(...) before the router mounts is itself safe
// (GoRouter holds its own RouterState), so the buffer is belt-and-suspenders.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import 'package:mosh/src/deeplink/mosh_url_scheme_windows.dart';
import 'package:mosh/src/routing/app_router.dart';

/// Handle returned by [startMoshDeepLinkIntake]; cancel it (e.g. in tests)
/// to stop the subscription and clear the replay buffer.
class MoshDeepLinkIntake {
  MoshDeepLinkIntake._(this._subscription);

  final StreamSubscription<Uri> _subscription;
  bool _disposed = false;

  /// Stops listening and releases the subscription. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingJoinUri = null;
    _subscription.cancel();
  }
}

/// The URI we will pre-fill into /join once the router is ready. Module-level
/// so the post-frame replay closure can read it without capturing `this`.
/// Null once consumed.
String? _pendingJoinUri;

/// True once the first frame has run, i.e. the GoRouter's navigator is
/// mounted and appRouter.go(...) can be called directly from a listener.
bool _routerReady = false;

/// Resets the module-level intake state. Intended for tests that pump a
/// fresh app + intake and need a clean slate (the post-frame flag and the
/// pending-URI buffer are process-global). Production code never calls this.
@visibleForTesting
void resetMoshDeepLinkIntakeStateForTest() {
  _pendingJoinUri = null;
  _routerReady = false;
}

/// Starts the `mosh://` deep-link intake. Call once from main() AFTER
/// RustLib.init() and the Windows scheme registration and BEFORE runApp,
/// so the stream subscription is in place to receive the cold-start
/// initial link (which app_links delivers shortly after runApp builds the
/// first frame).
///
/// Subscribes to [linkStream] (default: `AppLinks().uriLinkStream`). For
/// each Uri whose scheme is [kMoshUrlScheme] ('mosh'), navigates to
/// [AppRoutes.join] carrying the raw URI string as `extra` (the /join
/// route builder seeds the InvitePasteScreen text field from it). URIs
/// with any other scheme are ignored (ADR 0015: single mosh:// scheme).
///
/// Returns a [MoshDeepLinkIntake] whose lifetime bounds the subscription;
/// in production it lives for the whole process, so the handle is usually
/// discarded. Tests keep the handle so they can dispose the intake.
/// The optional [linkStream] is the single test seam: tests inject a
/// `StreamController<Uri>` so they can push a `mosh://` URI without the
/// Windows app_links plugin (which is absent under `flutter test`).
/// Production calls omit it and get the real app_links stream.
MoshDeepLinkIntake startMoshDeepLinkIntake({Stream<Uri>? linkStream}) {
  // Default to the app_links singleton stream (factory singleton, 7.2.1).
  final source = linkStream ?? AppLinks().uriLinkStream;
  final subscription = source.listen(
    _handleLink,
    onError: (Object e, StackTrace st) =>
        debugPrint('mosh: deep-link stream error: $e\n$st'),
  );
  // Mark the router ready on the first frame. Any link that arrived before
  // this point is held in _pendingJoinUri and replayed here once.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _routerReady = true;
    final pending = _pendingJoinUri;
    if (pending != null) {
      _pendingJoinUri = null;
      _goJoin(pending);
    }
  });
  return MoshDeepLinkIntake._(subscription);
}

/// Route a single incoming link to /join (mosh scheme only).
void _handleLink(Uri uri) {
  if (uri.scheme != kMoshUrlScheme) {
    // ADR 0015: single mosh:// scheme. Ignore anything else (e.g. a
    // stray https link, or a future per-fork scheme we do not honor here).
    return;
  }
  final value = uri.toString();
  if (_routerReady) {
    _goJoin(value);
  } else {
    // Link arrived before the first frame (the narrow cold-start race).
    // Stash it; the post-frame callback replays exactly one.
    _pendingJoinUri = value;
  }
}

/// Navigate to /join carrying the raw URI string as `extra`. The /join
/// route builder reads state.extra and seeds InvitePasteScreen.
void _goJoin(String inviteUri) {
  try {
    appRouter.go(AppRoutes.join, extra: inviteUri);
  } catch (e, st) {
    // Never let a navigation failure crash the link stream listener.
    debugPrint('mosh: failed to navigate to /join for $inviteUri: $e\n$st');
  }
}
