// Peer-status modal drawer, 1-to-1 with React's
// `src/features/private-dm/DiagnosticsDrawer.tsx`. The drawer branches the
// content exactly like React (lines ~78-86):
//   `session ? SessionDiagnostics : channel ? ChannelDiagnostics
//    : group ? GroupDiagnostics : NoActiveSession`
// Callers pass whichever of `session` / `channel` / `group` is active for
// their screen (DM -> session, ChannelScreen -> channel, GroupScreen ->
// group); the other two stay null. The `diagnosticsSummary` (already
// extended to all four branches) and the `ChannelDiagnostics` /
// `GroupDiagnostics` section widgets (already implemented) are reused here
// without re-implementing them -- DRY + orthogonality. This widget only
// owns the overlay chrome (backdrop + right aside + header + scrollable
// content column) and the localized copy seam (`AppLocalizations`).
//
// The React trigger lives in the titlebar with `aria-label="Open peer
// status"`; the Flutter DM/Channel/Group screens surface the equivalent as
// an AppBar action. The overlay is rendered by the host screen as a
// `Positioned.fill` child of a `Stack` over the body, so the composer +
// message list stay interactive when the drawer is closed and are covered
// while it is open.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/features/diagnostics/channel_group_diagnostics.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/features/diagnostics/summary_card.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

/// Modal overlay mirroring React `DiagnosticsDrawer`. Renders a
/// full-screen translucent backdrop that closes the drawer on tap (React
/// `role="presentation" onClick={onClose}`), and a right-side `aside` panel
/// (the drawer) with a header and a scrollable content column.
///
/// Exactly one of `session`, `channel`, or `group` is non-null when a
/// conversation is active; when all three are null the drawer renders the
/// idle/error fallback via `NoActiveSession` (mirrors React's final branch).
/// `session` is the live `SessionSnapshot` from `activeSessionProvider`
/// (DM screen); `channel` the `ChannelSnapshot` from
/// `channelSnapshotProvider` (ChannelScreen); `group` the `GroupSnapshot`
/// from `groupSnapshotProvider` (GroupScreen).
/// `error` is a runtime error string to surface via `RuntimeError`, or null.
/// `refreshing` toggles the refresh button (disabled while a refresh is
/// in flight). `onRefresh` / `onClose` are the header button callbacks.
class PeerStatusDrawer extends StatefulWidget {
  const PeerStatusDrawer({
    super.key,
    this.session,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
    required this.onClose,
    this.channel,
    this.group,
  });

  /// The active DM's `SessionSnapshot`, or null when no DM is active.
  final SessionSnapshot? session;

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
  // React `useModalFocus` keeps a single focus target for the modal; the
  // Flutter equivalent is a [FocusNode] owned here and attached to a
  // [KeyboardListener] wrapping the overlay. Autofocus pulls focus into
  // the drawer on mount (React `first.focus()`), and the key handler
  // forwards Esc to `onClose` (React `onKeyDown` Escape branch). The call
  // modals (`IncomingCallModal` / `OutgoingCallModal`) use the same
  // `KeyboardListener`-Esc pattern; this drawer matches them because it
  // is a `Positioned.fill` overlay (no `showDialog` route to lean on).
  late final FocusNode _focusNode = FocusNode(debugLabel: 'PeerStatusDrawer');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // React: `diagnostics-drawer-backdrop` + `role="presentation"`
    // onClick={onClose}. A `GestureDetector` on the backdrop is the Flutter
    // idiom; the aside swallows taps so they do not close the drawer
    // (React `onClick={(e) => e.stopPropagation()}`).
    //
    // The `KeyboardListener` is the outermost node so Esc is caught
    // before the backdrop's `GestureDetector` (and before any child
    // focusables) -- it is the `useModalFocus` keydown equivalent.
    // `autofocus: true` pulls focus into the drawer on open (React
    // `first.focus()`); the `FocusScope` is implicit in `KeyboardListener`.
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        // React: `if (event.key === 'Escape') { stopPropagation(); onEscape(); }`.
        // `KeyDownEvent` only -- not `KeyRepeatEvent`/`KeyUpEvent` -- so a
        // held Esc does not fire `onClose` repeatedly.
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: ColoredBox(
          // `.diagnostics-drawer-backdrop { background: rgba(0,0,0,0.34) }`.
          color: Colors.black.withValues(alpha: 0.34),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              // Swallow taps inside the panel so only the backdrop closes.
              onTap: () {},
              child: ConstrainedBox(
                // `.diagnostics-drawer { width: min(392px, 100vw - 24px) }`.
                constraints: BoxConstraints(
                  maxWidth: math.min(
                    392,
                    MediaQuery.sizeOf(context).width - 24,
                  ),
                ),
                child: Semantics(
                  label: l.peerStatusTitle,
                  container: true,
                  // `scopesRoute: true` mirrors React `aria-modal="true"`
                  // (it scopes the route so the drawer is announced as a
                  // modal boundary); `label` is the `aria-labelledby` title.
                  // `explicitChildNodes: true` is REQUIRED by the framework
                  // when `scopesRoute` is true (RenderObject assertion), so
                  // the drawer's own semantics children stay visible under
                  // the scoped node instead of being merged up.
                  explicitChildNodes: true,
                  scopesRoute: true,
                  // ModalFocusTrap goes inside the outer backdrop listener and semantics
                  // so Tab/Shift+Tab focus cycling is applied to the drawer contents.
                  child: ModalFocusTrap(
                    child: Material(
                      // `.diagnostics-drawer { background: var(--bg-0);
                      // border-left: 1px solid var(--line) }` -- the panel
                      // drops below the --bg-1 window, it does not match it.
                      color: MoshColors.bg0,
                      elevation: 0,
                      shape: const Border(
                        left: BorderSide(color: MoshColors.line),
                      ),
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
                              child: _DrawerContent(
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawer header: plug icon + h2 title + refresh + close `IconButton`s.
/// Mirrors React's `<header>` (IconPlugConnected size=16, h2 "Peer status",
/// IconRefresh size=14 disabled while refreshing, IconX size=14).
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
          // React: <IconPlugConnected size=16 />. The closest material icon
          // is `Icons.electrical_services` (a plug), matching the trigger
          // used on the DM/Channel/Group screens' AppBar action for visual
          // consistency.
          const Icon(Icons.electrical_services, size: 16),
          const SizedBox(width: 8),
          // React: <h2 id="diagnostics-title">Peer status</h2>.
          Expanded(
            // `.diagnostics-drawer > header h2 { font-size: 12px;
            // text-transform: uppercase; letter-spacing: 0.08em; color:
            // var(--fg-2) }`.
            // Flutter has no text-transform, so the string itself is
            // uppercased; the Semantics label keeps the natural-case name
            // the DOM text carries in React.
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

/// The scrollable content column: SummaryCard, then RuntimeError (if any),
/// then the active conversation's diagnostics section, else NoActiveSession.
/// Branch order matches React `DiagnosticsDrawer` lines ~78-86 exactly:
/// `session ? SessionDiagnostics : channel ? ChannelDiagnostics
///  : group ? GroupDiagnostics : NoActiveSession`.
class _DrawerContent extends StatelessWidget {
  const _DrawerContent({
    this.session,
    required this.channel,
    required this.group,
    required this.error,
  });

  final SessionSnapshot? session;
  final ChannelSnapshot? channel;
  final GroupSnapshot? group;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final summary = diagnosticsSummary(
        l: l, session: session, channel: channel, group: group, error: error);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SummaryCard(summary: summary),
          if (error != null) ...[
            const SizedBox(height: 12),
            RuntimeError(message: error!),
          ],
          const SizedBox(height: 12),
          if (session != null)
            SessionDiagnostics(session: session!)
          else if (channel != null)
            ChannelDiagnostics(channel: channel!)
          else if (group != null)
            GroupDiagnostics(group: group!)
          else
            const NoActiveSession(),
        ],
      ),
    );
  }
}
