import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/channel_screen.dart';
import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/features/settings/settings_screen.dart'
    show SettingsScreen;

import 'package:mosh/src/routing/mosh_shell.dart';

/// Canonical route paths. Kept as constants so S2-3 deep-link intake and any
/// in-app `context.go(...)` callers reference one source of truth.
class AppRoutes {
  const AppRoutes._();

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

  /// Standalone settings above the preserved chat route.
  static const String settings = '/settings';

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
  // After FirstRunGate finishes, the app opens the StatefulShellRoute:
  // branch A (/sessions, the SessionRail) on the left and branch B
  // (/chat, ChatPaneWelcome with the inline NewSessionPanel) on the right
  // on desktop, branch A alone on mobile. MoshApp defers mounting this
  // router during first-run setup while retaining an incoming invite.
  // The start menu lives in the chat pane at /chat.
  initialLocation: AppRoutes.sessions,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.settings,
      builder: (BuildContext context, GoRouterState state) =>
          const SettingsScreen(),
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
    // Two-pane shell. The rail (branch A, /sessions) + the chat (branch B,
    // /chat welcome + /dm/:id + /channel/:name + /group/:groupId) share
    // one StatefulShellRoute. The navigatorContainerBuilder (MoshShell)
    // lays them out side-by-side on desktop (rail always visible beside
    // the chat) and as a single pane on mobile (rail OR chat). go_router
    // auto-activates the branch matching the destination, so the rail's
    // context.go(AppRoutes.dmFor(...)) + the chat's context.go(AppRoutes
    // .sessions) Just Work without any screen edits -- the rail rows stay
    // mounted on desktop while the chat pane swaps, and on mobile the
    // active branch swaps (the rail hides when the chat opens).
    StatefulShellRoute(
      navigatorContainerBuilder: (context, shell, children) => MoshShell(
        currentIndex: shell.currentIndex,
        children: children,
      ),
      builder: (context, state, navigationShell) => navigationShell,
      branches: <StatefulShellBranch>[
        // Branch A (the rail). The SessionsScreen renders the combined
        // rail (DM sessions + groups + channels + orgs). On desktop this
        // is the left pane (fixed width 300); on mobile it is the only
        // pane when no chat is open. The row onTap navigates to a branch
        // B route, which go_router auto-activates (no goBranch call here).
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              // DM sessions list.
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
              // Chat-pane welcome: the NewSessionPanel is rendered inline
              // at every viewport size.
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
