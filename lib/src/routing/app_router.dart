// S2-1: named-route shell. Replaces the static `MoshHome` smoke screen so the
// slice-one screens (onboarding, invite-paste, dm, diagnostics) become
// reachable from the running app. Uses `go_router` (declarative, URL-based)
// so the S2-3 deep-link intake (`mosh://...` -> route) can map straight onto
// these path strings instead of hand-rolling `Navigator.pushNamed`.
//
// Route table (path -> screen):
//   /                 OnboardingScreen (home; matches the React entry flow)
//   /join             InvitePasteScreen
//   /sessions         SessionsScreen (DM sessions list; React SessionRail)
//   /dm/:sessionId    DmScreen(sessionId = state.pathParameters['sessionId'])
//
// Two-pane shell (React private-dm-screen desktop-body parity): the
// /sessions, /dm/:id, /channel/:name, /group/:groupId, and /chat (welcome)
// routes live inside a StatefulShellRoute with TWO branches:
//   - branch A (rail):  /sessions (SessionsScreen)
//   - branch B (chat):  /chat (ChatPaneWelcome) + /dm/:id + /channel/:name
//                       + /group/:groupId
// The shell (mosh_shell.dart) lays them out side-by-side on desktop (rail
// always visible beside the chat -- the parity gap) and as a single pane
// on mobile (rail OR chat, mirroring React's useConversationRailState).
//
// `DmScreen` already takes `sessionId` as a required constructor arg, so the
// route feeds it from the path parameter (typed String). No screen internals
// are touched. `MoshApp` keeps ProviderScope at root + MaterialApp theming
// + localization; only `home:` -> `MaterialApp.router(routerConfig:)` swaps in.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/channel_screen.dart';
import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';

import 'package:mosh/src/features/onboarding/chat_create_screen.dart';
import 'package:mosh/src/features/onboarding/channel_join_screen.dart';
import 'package:mosh/src/features/onboarding/group_create_screen.dart';

import 'package:mosh/src/routing/mosh_shell.dart';

/// Canonical route paths. Kept as constants so S2-3 deep-link intake and any
/// in-app `context.go(...)` callers reference one source of truth.
class AppRoutes {
  const AppRoutes._();

  static const String onboarding = '/';
  static const String join = '/join';
  static const String sessions = '/sessions';
  // Branch B (chat) default location -- the welcome pane shown when no
  // conversation is open (desktop right pane / mobile chat branch initial).
  // Reached by the chat screens' leave (context.go stays on the rail branch)
  // and as branch B's initial location.
  static const String chat = '/chat';
  static const String dm = '/dm';
  static const String channel = '/channel';

  static const String group = '/group';

  /// Chat-create step route (1-в-1 with React's ChatCreateStep). Reached
  /// from the onboarding Chat tile.
  static const String chatCreate = '/chat-create';

  /// Channel-join step route (1-в-1 with React's ChannelJoinStep). Reached
  /// from the onboarding Channel tile.
  static const String channelJoin = '/channel-join';

  /// Group-create step route (1-в-1 with React's GroupCreateStep). Reached
  /// from the onboarding Group tile.
  static const String groupCreate = '/group-create';

  /// Builds a `/dm/<sessionId>` location string. Centralized so callers do
  /// not concatenate paths by hand (and S2-3 can resolve an invite's
  /// sessionId to a route in one place).
  static String dmFor(String sessionId) => '$dm/$sessionId';

  /// Builds a `/channel/<name>` location string. Centralized so callers do
  /// not concatenate paths by hand; mirrors [dmFor] for the channel screen.
  static String channelFor(String name) => '$channel/$name';

  /// Builds a `/group/<groupId>` location string. Centralized so callers do
  /// not concatenate paths by hand; mirrors [channelFor] / [dmFor] for the
  /// group screen. Keyed by `groupId` (the group identity), not a name.
  static String groupFor(String groupId) => '$group/$groupId';
}

/// The app's [GoRouter]. Stateless + global: it holds no per-session state,
/// only declarative route -> screen mappings. `MoshApp` passes it to
/// `MaterialApp.router` (which preserves locale/theme/localization wiring).
final GoRouter appRouter = GoRouter(
  // App opens directly inside the StatefulShellRoute (mosh_shell.dart):
  // branch A (/sessions, the SessionRail) on the left and branch B
  // (/chat, ChatPaneWelcome with the inline NewSessionPanel) on the right
  // on desktop, branch A alone on mobile. This mirrors the React app,
  // where App.tsx renders <PrivateDmScreen/> immediately with no
  // onboarding gate. The `/` onboarding route (OnboardingScreen with its
  // tiles + the AppBar diagnostics action) remains reachable by
  // navigation -- it is just no longer the initial location.
  initialLocation: AppRoutes.sessions,
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
      // Chat-create step (1-в-1 with React's ChatCreateStep). Reached from
      // the onboarding Chat tile via context.go(AppRoutes.chatCreate); the
      // step's Back button returns to AppRoutes.onboarding. The group /
      // join / channel step routes are deferred to later atomics.
      path: AppRoutes.chatCreate,
      builder: (BuildContext context, GoRouterState state) =>
          const ChatCreateScreen(),
    ),
    GoRoute(
      // Channel-join step (1-в-1 with React's ChannelJoinStep). Reached from
      // the onboarding Channel tile via context.go(AppRoutes.channelJoin);
      // the step's Back button returns to AppRoutes.onboarding. The Join
      // button is a NO-OP STUB (the bridge joinChannel seam is a later slice).
      path: AppRoutes.channelJoin,
      builder: (BuildContext context, GoRouterState state) =>
          const ChannelJoinScreen(),
    ),
    GoRoute(
      // Group-create step (1-в-1 with React's GroupCreateStep). Reached from
      // the onboarding Group tile via context.go(AppRoutes.groupCreate);
      // the step's Back button returns to AppRoutes.onboarding. The Create
      // button is a NO-OP STUB (the bridge createGroup seam is a later slice).
      path: AppRoutes.groupCreate,
      builder: (BuildContext context, GoRouterState state) =>
          const GroupCreateScreen(),
    ),
    // Two-pane shell -- the React private-dm-screen desktop-body port. The
    // rail (branch A, /sessions) + the chat (branch B, /chat welcome +
    // /dm/:id + /channel/:name + /group/:groupId) share one
    // StatefulShellRoute. The navigatorContainerBuilder (MoshShell) lays
    // them out side-by-side on desktop (rail always visible beside the
    // chat) and as a single pane on mobile (rail OR chat). go_router
    // auto-activates the branch matching the destination, so the rail's
    // context.go(AppRoutes.dmFor(...)) + the chat's context.go(AppRoutes
    // .sessions) Just Work without any screen edits -- the rail rows stay
    // mounted on desktop while the chat pane swaps, and on mobile the
    // active branch swaps (the rail hides when the chat opens).
    StatefulShellRoute.indexedStack(
      builder: (BuildContext context, GoRouterState state,
          StatefulNavigationShell navigationShell) {
        return StatefulNavigationShell(
          shellRouteContext: navigationShell.shellRouteContext,
          router: GoRouter.of(context),
          containerBuilder: (BuildContext c, StatefulNavigationShell shell,
                  List<Widget> children) =>
              MoshShell(
            currentIndex: shell.currentIndex,
            children: children,
          ),
        );
      },
      branches: <StatefulShellBranch>[
        // Branch A (the rail). The SessionsScreen renders the combined
        // rail (DM sessions + groups + channels + orgs). On desktop this
        // is the left pane (fixed width 300); on mobile it is the only
        // pane when no chat is open. The row onTap navigates to a branch
        // B route, which go_router auto-activates (no goBranch call here).
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              // DM sessions list (React SessionRail sessions section).
              path: AppRoutes.sessions,
              builder: (BuildContext context, GoRouterState state) =>
                  const SessionsScreen(),
            ),
          ],
        ),
        // Branch B (the chat). The welcome pane (/chat) is the initial
        // location so the desktop right pane is never blank before a
        // conversation opens. The DM/channel/group routes are
        // byte-identical to the prior flat routes -- they become branch B
        // content. The chat screens' context.go(AppRoutes.sessions) on
        // leave routes to branch A (rail visible on desktop, swap on
        // mobile) -- no chat-screen edits needed.
        StatefulShellBranch(
          initialLocation: AppRoutes.chat,
          // preload so the desktop right pane renders the welcome pane
          // (branch B's initial location) even before the user opens a
          // conversation. go_router only builds an inactive branch's
          // Navigator when it is the active branch or preloaded; without
          // this the desktop two-pane Row would show a blank right pane
          // (a SizedBox.shrink) until a DM is opened. Mobile is unaffected
          // (the chat branch is offstage until activated anyway).
          preload: true,
          routes: <RouteBase>[
            GoRoute(
              // Chat-pane welcome: the existing NewSessionPanel is rendered
              // inline at every viewport size, matching React's showSetup path.
              path: AppRoutes.chat,
              builder: (BuildContext context, GoRouterState state) =>
                  const ChatPaneWelcome(),
            ),
            GoRoute(
              path: '${AppRoutes.dm}/:sessionId',
              builder: (BuildContext context, GoRouterState state) {
                final sessionId = state.pathParameters['sessionId']!;
                return DmScreen(sessionId: sessionId);
              },
            ),
            GoRoute(
              path: '${AppRoutes.channel}/:name',
              builder: (BuildContext context, GoRouterState state) {
                final name = state.pathParameters['name']!;
                return ChannelScreen(name: name);
              },
            ),
            GoRoute(
              path: '${AppRoutes.group}/:groupId',
              builder: (BuildContext context, GoRouterState state) {
                final groupId = state.pathParameters['groupId']!;
                return GroupScreen(groupId: groupId);
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
