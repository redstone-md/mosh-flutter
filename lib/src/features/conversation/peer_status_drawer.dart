// Peer-status modal drawer. The drawer branches the content:
//   `session ? SessionDiagnostics : channel ? ChannelDiagnostics
//    : group ? GroupDiagnostics : NoActiveSession`
// Callers pass whichever of `session` / `channel` / `group` is active for
// their screen (DM -> session, ChannelScreen -> channel, GroupScreen ->
// group); the other two stay null. The `diagnosticsSummary` and the
// `ChannelDiagnostics` / `GroupDiagnostics` section widgets are reused here
// without re-implementing them -- DRY + orthogonality. This widget only
// owns the overlay chrome (backdrop + right aside + header + scrollable
// content column) and the localized copy seam (`AppLocalizations`).
//
// The DM/Channel/Group screens surface the trigger as an AppBar action.
// The overlay is rendered by the host screen as a `Positioned.fill` child
// of a `Stack` over the body, so the composer + message list stay
// interactive when the drawer is closed and are covered while it is open.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:flutter/services.dart';
import 'package:mosh/src/features/conversation/conversation_diagnostics_content.dart';

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
/// `error` is a runtime error string to surface via `RuntimeError`, or null.
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

  /// A runtime error to surface via `RuntimeError`, or null.
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
              // 34% black scrim.
              color: Colors.black.withValues(alpha: 0.34),
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
      // At most 392px wide, or viewport minus 24px.
      constraints: BoxConstraints(
        maxWidth: math.min(392, MediaQuery.sizeOf(context).width - 24),
      ),
      // `scopesRoute` announces the drawer as a modal boundary named by
      // `label`; the framework requires `explicitChildNodes` with it.
      child: Semantics(
        label: widget.panel == null ? l.peerStatusTitle : l.chatDetailsTitle,
        container: true,
        explicitChildNodes: true,
        scopesRoute: true,
        child: widget.panel ??
            Material(
              // bg-0 panel with a hairline left border: it drops below the
              // bg-1 window, it does not match it.
              color: MoshColors.bg0,
              elevation: 0,
              shape: const Border(left: BorderSide(color: MoshColors.line)),
              child: SizedBox.expand(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DrawerHeader(
                      title: l.peerStatusTitle,
                      refreshTooltip: l.refreshStatus,
                      closeTooltip: l.closePeerStatus,
                      refreshing: widget.refreshing,
                      onRefresh: widget.onRefresh,
                      onClose: widget.onClose,
                    ),
                    Expanded(
                      child: ConversationDiagnosticsContent(
                        session: widget.session,
                        channel: widget.channel,
                        group: widget.group,
                        error: widget.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

/// The drawer header: plug icon + title + refresh + close `IconButton`s
/// (refresh disabled while refreshing).
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.title,
    required this.refreshTooltip,
    required this.closeTooltip,
    required this.refreshing,
    required this.onRefresh,
    required this.onClose,
  });

  final String title;
  final String refreshTooltip;
  final String closeTooltip;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MoshColors.line)),
      ),
      child: Row(
        children: [
          // A plug glyph, matching the trigger used on the DM/Channel/Group
          // screens' AppBar action for visual consistency.
          const Icon(Icons.electrical_services_outlined, size: 16),
          const SizedBox(width: 8),
          // Uppercase 12px title with wide letter spacing in fg-2.
          // Flutter has no text-transform, so the string itself is
          // uppercased; the Semantics label keeps the natural-case name.
          Expanded(
            child: Semantics(
              label: title,
              excludeSemantics: true,
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.08 * 12,
                  color: MoshColors.fg2,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: refreshTooltip,
            icon: const Icon(Icons.refresh, size: 14),
            onPressed: refreshing ? null : onRefresh,
            visualDensity: VisualDensity.compact,
            splashRadius: 18,
          ),
          IconButton(
            tooltip: closeTooltip,
            icon: const Icon(Icons.close, size: 14),
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}
