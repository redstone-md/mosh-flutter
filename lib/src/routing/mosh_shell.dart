// Two-pane desktop shell -- the Flutter port of React's private-dm-screen
// desktop-body (private-dm-screen.tsx:243-343): the SessionRail stays
// ALWAYS visible beside the active chat-pane on desktop, and collapses
// to a single-pane on mobile (use-conversation-rail-state.ts:1-38). Until
// now Flutter used flat go-routes (/sessions <-> /dm/:id), so selecting
// a session did a full route swap and the rail DISAPPEARED while reading
// a DM -- the user could not see the inbox while chatting. This shell
// closes that gap by mounting the two StatefulShellRoute branches
// side-by-side on desktop and switching between them on mobile.
//
// The shell is a pure layout widget: it owns NO state. It is wired as the
// StatefulShellRoute navigatorContainerBuilder, so it receives the two
// branch Navigator widgets (children) + the currentIndex and lays them
// out. Branch A (index 0) is the rail (/sessions -> SessionsScreen);
// branch B (index 1) is the chat (/dm/:id, /channel/:name, /group/:groupId,
// and the /chat welcome default). The rail active-highlight (8f34256)
// already tracks the open conversation via activeConversationKeyProvider,
// so the shell only needs to keep the rail mounted -- it does not touch
// the highlight logic.
//
// Layout:
//   - Desktop (width > 580, the React @media (max-width: 580px) inverse):
//     a Row with the rail branch (fixed width 300, the React rail width)
//     + a VerticalDivider + an Expanded chat branch. Both branches are
//     ALWAYS mounted (the rail stays while a DM is open -- the parity gap).
//   - Mobile (width <= 580): the go_router default IndexedStack (the
//     _IndexedStackedRouteBranchContainer: Offstage + TickerMode + stack)
//     so only the ACTIVE branch renders but the inactive branch's
//     Navigator state is preserved (keep-alive). The rail's onTap does
//     context.go(AppRoutes.dmFor(...)); go_router auto-activates branch B
//     (the route lives in branch B), so the rail swaps to the chat. The
//     chat's back/leave does context.go(AppRoutes.sessions) -> branch A,
//     swapping back to the rail. Mirrors React's useConversationRailState
//     rail-or-chat toggle (the rail is NOT shown over the chat on mobile).
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';

/// Desktop rail pane width -- the React SessionRail fixed width. Kept
/// fixed (not responsive) so the chat pane gets the remaining space, 1-1
/// with the React desktop-body rail column.
const double _kRailWidth = 300.0;

/// The two-pane shell container -- wired as the StatefulShellRoute
/// navigatorContainerBuilder. Receives the two branch Navigator widgets
/// (children) + the active branch index and lays them out responsively.
/// See the file header for the desktop vs mobile behavior and the React
/// parity rationale.
///
/// Branch indices are fixed by the router (branch 0 = rail, branch 1 =
/// chat). The shell never calls goBranch itself -- navigation is driven
/// by context.go(...) from the rail rows + chat screens, and go_router
/// auto-activates the matched branch. The shell only LAYS OUT whatever
/// branch is active (mobile) or both (desktop).
class MoshShell extends StatelessWidget {
  const MoshShell({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  /// The active branch index (0 = rail, 1 = chat). Drives the mobile
  /// IndexedStack index; ignored on desktop (both branches are live).
  final int currentIndex;

  /// The per-branch Navigator widgets (index 0 = rail, index 1 = chat).
  /// Provided by the StatefulShellRoute navigatorContainerBuilder.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Desktop: rail + chat side-by-side, both ALWAYS visible (the parity
    // gap -- the rail stays while a DM is open). Mobile: the go_router
    // default IndexedStack container, so only the active branch shows
    // while the inactive branch's Navigator state is preserved.
    if (isMobileBreakpoint(context)) {
      return _MobileShell(currentIndex: currentIndex, children: children);
    }
    return Row(
      children: <Widget>[
        // Branch A (the rail). Fixed width so the chat pane gets the rest.
        SizedBox(width: _kRailWidth, child: children[0]),
        const VerticalDivider(width: 1, thickness: 1),
        // Branch B (the chat). Expanded so it fills the remaining width.
        Expanded(child: children[1]),
      ],
    );
  }
}

/// Mobile shell -- the go_router default _IndexedStackedRouteBranchContainer
/// port (Offstage + TickerMode + IndexedStack) so the inactive branch's
/// Navigator state is preserved across the rail <-> chat round trip
/// (keep-alive). Replicated here (not re-imported: the go_router default is
/// private) so the mobile path keeps byte-identical keep-alive semantics to
/// the upstream StatefulShellRoute.indexedStack default.
class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.currentIndex, required this.children});

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> stackItems = children
        .asMap()
        .entries
        .map((e) => _branchContainer(currentIndex == e.key, e.value))
        .toList();
    return IndexedStack(index: currentIndex, children: stackItems);
  }

  Widget _branchContainer(bool isActive, Widget child) {
    return Offstage(
      offstage: !isActive,
      child: TickerMode(enabled: isActive, child: child),
    );
  }
}

/// The chat-pane welcome / empty state -- the Flutter port of React's
/// NewSessionPanel "no conversation open" arm (private-dm-screen.tsx
/// showWelcome). Rendered as branch B's default location (/chat) so the
/// desktop right pane is never blank before the user opens a conversation,
/// and so leaving a chat (context.go(AppRoutes.sessions)) on desktop can
/// reset branch B here instead of leaving a dead chat mounted. Reuses the
/// same ARB keys as the sessions empty state (chatNoSessionTitle +
/// chatNoSessionBody) so the wording stays DRY and consistent.
///
/// This is a PLACEHOLDER (not the React NewSessionPanel create/accept
/// form): wiring the create/accept flow into the welcome pane is a later
/// atomic. Here the pane just confirms the shell mounted branch B.
class ChatPaneWelcome extends StatelessWidget {
  const ChatPaneWelcome({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l.chatNoSessionTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l.chatNoSessionBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}