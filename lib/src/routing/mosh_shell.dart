// Two-pane desktop shell. The SessionRail stays ALWAYS visible beside the
// active chat pane on desktop and collapses to a single pane on mobile.
// Flat go-routes (/sessions <-> /dm/:id) would do a full route swap on
// every selection and the rail would DISAPPEAR while reading a DM. This
// shell avoids that by mounting the two StatefulShellRoute branches
// side-by-side on desktop and switching between them on mobile.
//
// The shell is a pure layout widget: it owns NO state. It is wired as the
// StatefulShellRoute navigatorContainerBuilder, so it receives the two
// branch Navigator widgets (children) + the currentIndex and lays them
// out. Branch A (index 0) is the rail (/sessions -> SessionsScreen);
// branch B (index 1) is the chat (/dm/:id, /channel/:name, /group/:groupId,
// and the /chat welcome default). The rail's active-highlight already
// tracks the open conversation via activeConversationKeyProvider, so the
// shell only needs to keep the rail mounted.
//
// Layout:
//   - Desktop (width > 580): a Column with the shared desktop titlebar
//     (mosh_title_bar.dart: brand + subtitle + Peer status button + live
//     StatePill) ABOVE a Row of the rail branch (kRailWidth) + a
//     VerticalDivider + an Expanded chat branch.
//     Both branches are ALWAYS mounted (the rail stays while a DM is
//     open). The titlebar's Peer status button opens the shell-level
//     PeerStatusDrawer as a Positioned.fill overlay over the whole shell
//     (the same overlay pattern the DM/Channel/Group screens use with
//     their own AppBar buttons).
//   - Mobile (width <= 580): the go_router default IndexedStack (the
//     _IndexedStackedRouteBranchContainer: Offstage + TickerMode + stack)
//     so only the ACTIVE branch renders but the inactive branch's
//     Navigator state is preserved (keep-alive). The rail's onTap does
//     context.go(AppRoutes.dmFor(...)); go_router auto-activates branch B,
//     so the rail swaps to the chat; the chat's back does
//     context.go(AppRoutes.sessions) -> branch A. DEVIATION: the shared
//     desktop titlebar is NOT mounted on mobile -- the mobile screens
//     already carry their own AppBar + peer-status button, so a second
//     titlebar would duplicate the Peer status entry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/features/onboarding/new_session_panel.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/features/sessions/rail_item.dart' show kRailWidth;
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/conversation_providers.dart'
    show invalidateConversation;
import 'package:mosh/src/state/session_providers.dart';

/// The two-pane shell container -- wired as the StatefulShellRoute
/// navigatorContainerBuilder. Receives the two branch Navigator widgets
/// (children) + the active branch index and lays them out responsively.
/// See the file header for the desktop vs mobile behavior.
///
/// The shell never calls goBranch itself -- navigation is driven by
/// context.go(...) from the rail rows + chat screens, and go_router
/// auto-activates the matched branch. The shell only LAYS OUT whatever
/// branch is active (mobile) or both (desktop).
///
/// A ConsumerStatefulWidget so the desktop titlebar's shell-level
/// PeerStatusDrawer toggle lives here: the shell both flips
/// `_showPeerStatus` AND mounts the Positioned.fill overlay. The titlebar
/// fires the shell-supplied `onOpenPeerStatus` callback and holds no
/// overlay state; the shell rebuilds on the flip, which is what makes the
/// drawer appear.
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
  // Shell-level PeerStatusDrawer visibility. The shell owns this toggle
  // AND mounts the Positioned.fill overlay, so flipping it rebuilds the
  // desktop Stack and the drawer appears.
  bool _showPeerStatus = false;

  @override
  Widget build(BuildContext context) {
    // Desktop: rail + chat side-by-side, both ALWAYS visible (the rail
    // stays while a DM is open). Mobile: the go_router default
    // IndexedStack container, so only the active branch shows while the
    // inactive branch's Navigator state is preserved.
    if (isMobileBreakpoint(context)) {
      return _MobileShell(
        currentIndex: widget.currentIndex,
        children: widget.children,
      );
    }
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            // Shared desktop titlebar. Sits ABOVE the rail+chat row,
            // full window width.
            MoshTitleBar(
              onOpenPeerStatus: () => setState(() => _showPeerStatus = true),
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  // Branch A (the rail). Fixed width so the chat pane gets
                  // the rest.
                  SizedBox(width: kRailWidth, child: widget.children[0]),
                  const VerticalDivider(width: 1, thickness: 1),
                  // Branch B (the chat). Expanded so it fills the remaining
                  // width.
                  Expanded(child: widget.children[1]),
                ],
              ),
            ),
          ],
        ),
        // Shell-level PeerStatusDrawer overlay: branch on the parsed
        // active kind to the matching snapshot family; null ->
        // PeerStatusDrawer renders NoActiveSession. onRefresh
        // invalidates the family entry.
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

  // The live DM SessionSnapshot for the active conversation, or null
  // (non-dm or loading/error). PeerStatusDrawer renders NoActiveSession
  // when all three snapshot getters return null.
  SessionSnapshot? _activeDmSession(WidgetRef ref) {
    final active = ref.watch(activeConversationProvider);
    if (active?.kind != ConversationKind.dm) return null;
    return ref.watch(activeSessionProvider(active!.arg)).value;
  }

  // The live ChannelSnapshot for the active conversation, or null
  // (non-channel or loading/error).
  ChannelSnapshot? _activeChannelSnapshot(WidgetRef ref) {
    final active = ref.watch(activeConversationProvider);
    if (active?.kind != ConversationKind.channel) return null;
    return ref.watch(channelSnapshotProvider(active!.arg)).value;
  }

  // The live GroupSnapshot for the active conversation, or null
  // (non-group or loading/error).
  GroupSnapshot? _activeGroupSnapshot(WidgetRef ref) {
    final active = ref.watch(activeConversationProvider);
    if (active?.kind != ConversationKind.group) return null;
    return ref.watch(groupSnapshotProvider(active!.arg)).value;
  }

  // A runtime error string for the active snapshot
  // (`async.hasError ? async.error.toString() : null`), or null when the
  // active family is loading/data or no conversation is open.
  String? _activeDrawerError(WidgetRef ref) {
    final active = ref.watch(activeConversationProvider);
    if (active == null) return null;
    final async = switch (active.kind) {
      ConversationKind.dm => ref.watch(activeSessionProvider(active.arg)),
      ConversationKind.channel =>
        ref.watch(channelSnapshotProvider(active.arg)),
      ConversationKind.group => ref.watch(groupSnapshotProvider(active.arg)),
    };
    return async.hasError ? async.error.toString() : null;
  }

  // Invalidates the active conversation's snapshot family entry so a
  // refresh re-runs the server query. No-op when nothing is open. Which
  // family that is belongs to the state layer, not here.
  void _invalidateActiveFamily() {
    final active = ref.read(activeConversationProvider);
    if (active == null) return;
    invalidateConversation(ref.invalidate, active.conversation);
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

/// The chat-pane welcome / empty-state, shown when no conversation is
/// open. Rendered as branch B's default slot so the desktop right pane
/// is never blank before a conversation opens, and so leaving a chat on
/// desktop resets branch B instead of leaving a dead chat mounted.
///
/// [NewSessionPanel] owns the local step state + the IndexedStack
/// keep-alive; the step success navigation (context.go channelFor /
/// groupFor / sessions) fires from within the steps and leaves the welcome
/// pane. It reads its own providers (inviteFlowProvider, gatewayProvider,
/// persistenceWarningProvider) via its ConsumerStatefulWidget ref.
class ChatPaneWelcome extends StatelessWidget {
  const ChatPaneWelcome({super.key});

  @override
  Widget build(BuildContext context) {
    final mobile = isMobileBreakpoint(context);
    return Scaffold(
      // On mobile this pane fills the window and the rail is offstage, so
      // without a header there is no way back to the conversation list --
      // the panel's own Back only returns to its step menu. Desktop keeps
      // the pane chrome-less: it is the right half of the two-pane shell.
      appBar: mobile
          ? AppBar(
              leading: railBackButton(context),
              title: Text(AppLocalizations.of(context)!.shellNewSession),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: isMobileBreakpoint(context)
                ? const EdgeInsets.all(24)
                : const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: const NewSessionPanel(),
            ),
          ),
        ),
      ),
    );
  }
}
