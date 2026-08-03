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
//     a Column with the shared desktop titlebar (mosh_title_bar.dart -- the
//     React header.titlebar port: brand + subtitle + Peer status button +
//     live StatePill) ABOVE a Row of the rail branch (fixed width 300, the
//     React rail width) + a VerticalDivider + an Expanded chat branch.
//     Both branches are ALWAYS mounted (the rail stays while a DM is open
//     -- the parity gap). The titlebar's Peer status button opens the
//     shell-level PeerStatusDrawer as a Positioned.fill overlay over the
//     whole shell (the same overlay pattern the DM/Channel/Group screens
//     use with their own AppBar buttons).
//   - Mobile (width <= 580): the go_router default IndexedStack (the
//     _IndexedStackedRouteBranchContainer: Offstage + TickerMode + stack)
//     so only the ACTIVE branch renders but the inactive branch's
//     Navigator state is preserved (keep-alive). The rail's onTap does
//     context.go(AppRoutes.dmFor(...)); go_router auto-activates branch B
//     (the route lives in branch B), so the rail swaps to the chat. The
//     chat's back/leave does context.go(AppRoutes.sessions) -> branch A,
//     swapping back to the rail. Mirrors React's useConversationRailState
//     rail-or-chat toggle (the rail is NOT shown over the chat on mobile).
//     DEVIATION: the shared desktop titlebar is NOT mounted on mobile --
//     the mobile screens already carry their own AppBar + peer-status
//     button (dm_screen.dart / channel_screen.dart / group_screen.dart),
//     so a second titlebar would duplicate the Peer status entry. React's
//     titlebar is desktop-only too (it sits in the desktop-body above the
//     rail+chat row; mobile renders the per-screen header instead).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/session_providers.dart';

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
/// A ConsumerStatefulWidget so the desktop titlebar's shell-level
/// PeerStatusDrawer toggle (`_showPeerStatus`) lives here -- the shell
/// both flips the toggle AND mounts the Positioned.fill overlay over the
/// desktop Column, mirroring dm_screen.dart L83 + L683-691 exactly (the
/// SAME widget owns the toggle AND mounts the overlay). The titlebar is
/// now a stateless-ish leaf that fires the shell-supplied
/// `onOpenPeerStatus` VoidCallback; it no longer holds the toggle or
/// exposes an overlay builder. This is what makes the drawer actually
/// appear: the shell rebuilds when it flips `_showPeerStatus` (the prior
/// titlebar-owned toggle did not, so the shell never re-rendered and the
/// tap silently no-opped).
class MoshShell extends ConsumerStatefulWidget {
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
  ConsumerState<MoshShell> createState() => _MoshShellState();
}

class _MoshShellState extends ConsumerState<MoshShell> {
  // Shell-level PeerStatusDrawer visibility -- mirrors the DM screen's
  // `_showPeerStatus` (dm_screen.dart L83). The shell owns this toggle
  // AND mounts the Positioned.fill overlay (dm_screen.dart L683-691), so
  // flipping it rebuilds the desktop Stack and the drawer appears.
  bool _showPeerStatus = false;

  @override
  Widget build(BuildContext context) {
    // Desktop: rail + chat side-by-side, both ALWAYS visible (the parity
    // gap -- the rail stays while a DM is open). Mobile: the go_router
    // default IndexedStack container, so only the active branch shows
    // while the inactive branch's Navigator state is preserved.
    if (isMobileBreakpoint(context)) {
      return _MobileShell(
          currentIndex: widget.currentIndex, children: widget.children);
    }
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            // Shared desktop titlebar (React header.titlebar). Sits ABOVE
            // the rail+chat row, full window width.
            MoshTitleBar(
              onOpenPeerStatus: () =>
                  setState(() => _showPeerStatus = true),
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  // Branch A (the rail). Fixed width so the chat pane gets
                  // the rest.
                  SizedBox(width: _kRailWidth, child: widget.children[0]),
                  const VerticalDivider(width: 1, thickness: 1),
                  // Branch B (the chat). Expanded so it fills the remaining
                  // width.
                  Expanded(child: widget.children[1]),
                ],
              ),
            ),
          ],
        ),
        // Shell-level PeerStatusDrawer overlay (mirrors dm_screen.dart
        // L683-691): the shell owns the toggle AND mounts the overlay.
        // Built directly here for the active conversation -- watch
        // activeConversationKeyProvider, branch on the key prefix
        // ('dm:' / 'channel:' / 'group:'), ref.watch the matching
        // FutureProvider.family, unwrap AsyncValue (null while
        // loading/error -- PeerStatusDrawer renders NoActiveSession when
        // all three are null), pass onRefresh (invalidate the matching
        // family entry) + onClose (flip the toggle).
        if (_showPeerStatus)
          Positioned.fill(
            child: PeerStatusDrawer(
              session: _activeDmSession(ref),
              channel: _activeChannelSnapshot(ref),
              group: _activeGroupSnapshot(ref),
              error: _activeDrawerError(ref),
              refreshing: false,
              onRefresh: _invalidateActiveFamily,
              onClose: () => setState(() => _showPeerStatus = false),
            ),
          ),
      ],
    );
  }

  // The active-conversation kind, parsed from the active key prefix.
  // Mirrors React's branch test on `activeSession` / `activeChannel` /
  // `activeGroup` (private-dm-screen.tsx L282-292). null when no
  // conversation is open. Defined here (not re-imported from the titlebar)
  // because the titlebar's copy is file-private; the shell needs its own
  // parse to build the drawer in build().
  _ActiveKind? _activeKind(WidgetRef ref) {
    final key = ref.watch(activeConversationKeyProvider);
    if (key == null) return null;
    if (key.startsWith('dm:')) return _ActiveKind.dm;
    if (key.startsWith('channel:')) return _ActiveKind.channel;
    if (key.startsWith('group:')) return _ActiveKind.group;
    return null;
  }

  // The family argument for the active conversation (sessionId / name /
  // groupId -- the suffix after the ':' prefix), or null when nothing is
  // open.
  String? _activeArg(WidgetRef ref) {
    final key = ref.watch(activeConversationKeyProvider);
    if (key == null) return null;
    if (key.startsWith('dm:')) return key.substring(3);
    if (key.startsWith('channel:')) return key.substring(8);
    if (key.startsWith('group:')) return key.substring(6);
    return null;
  }

  // The live DM SessionSnapshot for the active conversation, or null
  // (non-dm or loading/error). PeerStatusDrawer renders NoActiveSession
  // when all three snapshot getters return null.
  SessionSnapshot? _activeDmSession(WidgetRef ref) {
    final arg = _activeArg(ref);
    if (_activeKind(ref) != _ActiveKind.dm || arg == null) return null;
    return ref.watch(activeSessionProvider(arg)).value;
  }

  // The live ChannelSnapshot for the active conversation, or null
  // (non-channel or loading/error).
  ChannelSnapshot? _activeChannelSnapshot(WidgetRef ref) {
    final arg = _activeArg(ref);
    if (_activeKind(ref) != _ActiveKind.channel || arg == null) return null;
    return ref.watch(channelSnapshotProvider(arg)).value;
  }

  // The live GroupSnapshot for the active conversation, or null
  // (non-group or loading/error).
  GroupSnapshot? _activeGroupSnapshot(WidgetRef ref) {
    final arg = _activeArg(ref);
    if (_activeKind(ref) != _ActiveKind.group || arg == null) return null;
    return ref.watch(groupSnapshotProvider(arg)).value;
  }

  // A runtime error string for the active snapshot (mirrors dm_screen.dart
  // L507-508: `async.hasError ? async.error.toString() : null`), or null
  // when the active family is loading/data or no conversation is open.
  String? _activeDrawerError(WidgetRef ref) {
    final kind = _activeKind(ref);
    final arg = _activeArg(ref);
    if (kind == null || arg == null) return null;
    final async = switch (kind) {
      _ActiveKind.dm => ref.watch(activeSessionProvider(arg)),
      _ActiveKind.channel => ref.watch(channelSnapshotProvider(arg)),
      _ActiveKind.group => ref.watch(groupSnapshotProvider(arg)),
    };
    return async.hasError ? async.error.toString() : null;
  }

  // Invalidates the active conversation's snapshot family entry so a
  // refresh re-runs the server query (mirrors dm_screen.dart L688-689's
  // `ref.invalidate(activeSessionProvider(...))`). No-op when nothing is
  // open.
  void _invalidateActiveFamily() {
    final kind = _activeKind(ref);
    final arg = _activeArg(ref);
    if (kind == null || arg == null) return;
    switch (kind) {
      case _ActiveKind.dm:
        ref.invalidate(activeSessionProvider(arg));
      case _ActiveKind.channel:
        ref.invalidate(channelSnapshotProvider(arg));
      case _ActiveKind.group:
        ref.invalidate(groupSnapshotProvider(arg));
    }
  }
}

// The active-conversation kind for the shell's drawer build -- mirrors
// the titlebar's `_ActiveKind` enum (private there). Defined here so the
// shell can branch the snapshot family without exporting the titlebar's
// private enum.
enum _ActiveKind { dm, channel, group }

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
/// EmptyState (src/features/private-dm/ActiveChatPanes.tsx:407-418), the
/// inert desktop right pane shown at /chat when no conversation is open.
/// Rendered as branch B's default location so the desktop right pane is
/// never blank before the user opens a conversation, and so leaving a
/// chat (context.go(AppRoutes.sessions)) on desktop can reset branch B
/// here instead of leaving a dead chat mounted.
///
/// Layout mirrors React's EmptyState order 1:1: IconMessageCircle (28) ->
/// noSessionTitle -> noSessionBody -> primary startCta button with
/// IconPlus. The `onStart` callback is injected by the router
/// (app_router.dart), which routes it to context.go(AppRoutes.chatCreate)
/// -- the same route the onboarding Chat tile uses
/// (onboarding_screen.dart:90 _goChatCreate). This keeps the widget
/// testable (no context.go inside) and matches the sessions_screen.dart
/// _EmptyState.onStart pattern (sessions_screen.dart:461-478).
///
/// Parity note: React's onNew also calls setup.resetInviteState()
/// (private-dm-screen.tsx:329-336). The Flutter port has NO counterpart
/// -- inviteFlowProvider keeps lastInvite across screens intentionally
/// (no resetInviteState method exists); navigating to /chat-create is
/// the parity action.
class ChatPaneWelcome extends StatelessWidget {
  const ChatPaneWelcome({super.key, required this.onStart});

  /// Starts the chat-create flow (router passes
  /// `() => context.go(AppRoutes.chatCreate)`). Mirrors React's onNew.
  final VoidCallback onStart;

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.chat_outlined,
                  size: 28, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
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
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.add, size: 14),
                label: Text(l.chatStartCta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
