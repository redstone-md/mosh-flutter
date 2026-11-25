import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/connection_status_panel.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show kConversationPanelWidth;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

/// Modal overlay for the peer-status drawer. Renders a full-screen
/// translucent backdrop that closes the drawer on tap, and a right-side
/// panel with a header and a scrollable content column.
///
/// Exactly one of `session`, `channel`, or `group` is non-null when a
/// conversation is active; when all three are null the drawer renders the
/// idle/error fallback via `NoActiveSession`. `session` is the live
/// `SessionSnapshot` from `activeSessionProvider` (DM screen); `channel`
/// the `ChannelSnapshot` from `channelSnapshotProvider` (ChannelScreen);
/// `group` the `GroupSnapshot` from `groupSnapshotProvider` (GroupScreen).
/// `error` is a runtime error worded for the user, or null.
/// `refreshing` toggles the refresh button (disabled while a refresh is
/// in flight). `onRefresh` / `onClose` are the header button callbacks.
class PeerStatusDrawer extends StatefulWidget {
  const PeerStatusDrawer({
    super.key,
    this.session,
    this.panel,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
    required this.onClose,
    this.channel,
    this.group,
  });

  /// The active DM's `SessionSnapshot`, or null when no DM is active.
  final SessionSnapshot? session;

  /// Optional conversation details inside the existing modal focus boundary.
  final Widget? panel;

  /// The active public channel's `ChannelSnapshot`, or null when no
  /// channel is active (ChannelScreen host).
  final ChannelSnapshot? channel;

  /// The active private group's `GroupSnapshot`, or null when no group is
  /// active (GroupScreen host).
  final GroupSnapshot? group;

  /// A runtime error worded for the user, or null.
  final String? error;

  /// Whether a refresh is in flight (disables the refresh button).
  final bool refreshing;

  /// Invoked by the refresh `IconButton` in the header.
  final VoidCallback onRefresh;

  /// Invoked by the close `IconButton` and by tapping the backdrop.
  final VoidCallback onClose;

  @override
  State<PeerStatusDrawer> createState() => _PeerStatusDrawerState();
}

class _PeerStatusDrawerState extends State<PeerStatusDrawer> {
  // The drawer is a `Positioned.fill` overlay, not a route, so it does the
  // modal-route focus work itself: its own scope takes focus on open (Tab
  // wraps inside a scope by default), and the control that had focus
  // before gets it back on close.
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'PeerStatusDrawer');
  final FocusNode? _opener = FocusManager.instance.primaryFocus;

  @override
  void initState() {
    super.initState();
    // Post-frame: the scope node is attached once the first frame builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    final opener = _opener;
    if (opener != null && opener.context != null) opener.requestFocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Escape closes, whichever drawer control holds focus. BlockSemantics
    // hides the screen behind from screen readers while the drawer is up.
    // The backdrop's `GestureDetector` closes on tap; the panel swallows
    // taps so they do not close it.
    return BlockSemantics(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        },
        child: FocusScope(
          node: _scope,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: ColoredBox(
              color: MoshColors.of(context).scrim,
              // Inside the backdrop so the scrim still covers the status bar
              // and the cutout, but the panel itself clears them -- as a
              // `Positioned.fill` overlay it has no Scaffold or AppBar to
              // inset it, so its header drew under the cutout on Android.
              child: SafeArea(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    // Swallow taps inside the panel so only the backdrop
                    // closes.
                    onTap: () {},
                    child: _panel(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ConstrainedBox(
      // A panel beside the conversation on the desktop, a screen of its own
      // in a narrow window.
      constraints: BoxConstraints(
        maxWidth: isMobileBreakpoint(context)
            ? double.infinity
            : kConversationPanelWidth,
      ),
      // `scopesRoute` announces the drawer as a modal boundary named by
      // `label`; the framework requires `explicitChildNodes` with it.
      child: Semantics(
        label: widget.panel == null ? l.peerStatusTitle : l.chatDetailsTitle,
        container: true,
        explicitChildNodes: true,
        scopesRoute: true,
        child: widget.panel ??
            ConnectionStatusPanel(
              session: widget.session,
              channel: widget.channel,
              group: widget.group,
              error: widget.error,
              refreshing: widget.refreshing,
              onRefresh: widget.onRefresh,
              onClose: widget.onClose,
            ),
      ),
    );
  }
}
