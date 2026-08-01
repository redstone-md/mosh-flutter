// S2-1: named-route shell. Replaces the static `MoshHome` smoke screen so the
// slice-one screens (onboarding, invite-paste, dm, diagnostics) become
// reachable from the running app. Uses `go_router` (declarative, URL-based)
// so the S2-3 deep-link intake (`mosh://...` -> route) can map straight onto
// these path strings instead of hand-rolling `Navigator.pushNamed`.
//
// Route table (path -> screen):
//   /                 OnboardingScreen (home; matches the React entry flow)
//   /join             InvitePasteScreen
//   /sessions         SessionsScreen (DM sessions list; React SessionRail sessions section)
//   /dm/:sessionId    DmScreen(sessionId = state.pathParameters['sessionId'])
//   /diagnostics      DiagnosticsScreen
//
// `DmScreen` already takes `sessionId` as a required constructor arg, so the
// route feeds it from the path parameter (typed String). No screen internals
// are touched. `MoshApp` keeps ProviderScope at root + MaterialApp theming
// + localization; only `home:` -> `MaterialApp.router(routerConfig:)` swaps in.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/features/diagnostics/diagnostics_screen.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';

/// Canonical route paths. Kept as constants so S2-3 deep-link intake and any
/// in-app `context.go(...)` callers reference one source of truth.
class AppRoutes {
  const AppRoutes._();

  static const String onboarding = '/';
  static const String join = '/join';
  static const String sessions = '/sessions';
  static const String diagnostics = '/diagnostics';
  static const String dm = '/dm';

  /// Builds a `/dm/<sessionId>` location string. Centralized so callers do
  /// not concatenate paths by hand (and S2-3 can resolve an invite's
  /// sessionId to a route in one place).
  static String dmFor(String sessionId) => '$dm/$sessionId';
}

/// The app's [GoRouter]. Stateless + global: it holds no per-session state,
/// only declarative route -> screen mappings. `MoshApp` passes it to
/// `MaterialApp.router` (which preserves locale/theme/localization wiring).
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.onboarding,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (BuildContext context, GoRouterState state) =>
          const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.join,
      // S2-3: pass the deep-link URI through. The intake calls
      // appRouter.go(AppRoutes.join, extra: <uri string>); `extra` is an
      // untyped Object, so we narrow it to String? here. In-app navigation
      // (no extra) leaves the field empty for manual paste.
      builder: (BuildContext context, GoRouterState state) {
        final extra = state.extra;
        final initialInviteUri = extra is String ? extra : null;
        return InvitePasteScreen(initialInviteUri: initialInviteUri);
      },
    ),
    GoRoute(
      path: AppRoutes.diagnostics,
      builder: (BuildContext context, GoRouterState state) =>
          const DiagnosticsScreen(),
    ),
    GoRoute(
      // DM sessions list (React SessionRail sessions section). Wired as its
      // own atomic; the onboarding Chat tile is NOT redirected here yet (a
      // later atomic connects the home tile to /sessions). Initial location
      // stays '/' (onboarding) so existing flows are unchanged.
      path: AppRoutes.sessions,
      builder: (BuildContext context, GoRouterState state) =>
          const SessionsScreen(),
    ),
    GoRoute(
      // DmScreen takes sessionId as a required arg; carry it on the path so
      // the location is shareable / deep-linkable (S2-3 will re-use this).
      path: '${AppRoutes.dm}/:sessionId',
      builder: (BuildContext context, GoRouterState state) {
        final sessionId = state.pathParameters['sessionId']!;
        return DmScreen(sessionId: sessionId);
      },
    ),
  ],
);
