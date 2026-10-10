import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/features/sessions/sessions_list_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/desktop_chrome_scope.dart';

import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/active_peer_status_drawer.dart';
import 'package:mosh/src/features/onboarding/new_session_panel.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/features/sessions/rail_compact.dart'
    show expandChatList;
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/routing/rail_pane.dart';

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
/// Standalone/mobile layouts retain their local diagnostics overlay. The
/// integrated desktop frame provides the shared titlebar and diagnostics.
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
            child: ActivePeerStatusDrawer(
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
        if (!DesktopChromeScope.isPresent(context))
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
                    // A short pane (a phone with the keyboard up) can have
                    // less height than the padding.
                    minHeight:
                        math.max(0, constraints.maxHeight - vertical * 2),
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
