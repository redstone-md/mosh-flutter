import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/features/sessions/sessions_list_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/features/onboarding/new_session_panel.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/features/sessions/rail_compact.dart'
    show expandChatList;
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/routing/rail_pane.dart';
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
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              _focusSearch,
        },
        child: _panes(context),
      );

  void _focusSearch() {
    if (!isMobileBreakpoint(context)) {
      return expandChatList(ref, focusSearch: true);
    }
    context.go(AppRoutes.sessions);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(chatListSearchFocusProvider).requestFocus();
    });
  }

  Widget _panes(BuildContext context) {
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
        _desktopPanes(),
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

  // The titlebar above the rail + chat row. Each pane is its own semantics
  // container: a pushed chat route brings a ModalBarrier whose
  // BlockSemantics would otherwise hide the titlebar and the rail from
  // screen readers.
  Widget _desktopPanes() {
    return Column(
      children: <Widget>[
        _SemanticsPane(
          child: MoshTitleBar(
            onOpenPeerStatus: () => setState(() => _showPeerStatus = true),
          ),
        ),
        Expanded(
          child: RailPane(
            rail: _SemanticsPane(child: widget.children[0]),
            chat: _SemanticsPane(child: widget.children[1]),
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

  // What the drawer says about a failed read of the active snapshot, worded
  // from the error's kind (never the runtime's raw message), or null when
  // the active family is loading/data or no conversation is open.
  String? _activeDrawerError(WidgetRef ref) {
    final active = ref.watch(activeConversationProvider);
    if (active == null) return null;
    final async = switch (active.kind) {
      ConversationKind.dm => ref.watch(activeSessionProvider(active.arg)),
      ConversationKind.channel =>
        ref.watch(channelSnapshotProvider(active.arg)),
      ConversationKind.group => ref.watch(groupSnapshotProvider(active.arg)),
    };
    final error = async.error;
    if (error == null) return null;
    return ConversationActionError.of(error)
        .describe(AppLocalizations.of(context)!);
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

/// A shell pane as its own semantics container, so a modal barrier inside
/// one pane blocks only that pane's semantics.
class _SemanticsPane extends StatelessWidget {
  const _SemanticsPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, explicitChildNodes: true, child: child);
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
      // Side padding follows the pane, not the window: at 581px the
      // desktop pane is only ~312px wide.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final vertical = mobile ? 24.0 : 48.0;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: constraints.maxWidth < 400 ? 16 : 32,
                  vertical: vertical,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: NewSessionPanel(
                    minHeight: constraints.maxHeight - vertical * 2,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
