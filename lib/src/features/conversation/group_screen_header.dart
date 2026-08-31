// GroupScreen AppBar header -- the 1-в-1 port of React `ActiveChatHeader`
// (ActiveChatPanes.tsx ~L302-337), extracted from `group_screen.dart` to
// restore the 500-line headroom on the screen file. PURE REFACTOR: zero
// behavioral change vs the prior inline AppBar block.
//
// Owns the ENTIRE AppBar (two-line title Column + actions: admin-pill +
// copy-invite + peer-status + leave) and the copy-invite ephemeral state
// (`_inviteCopied` + `_inviteCopyTimer`, the 1600ms revert). Reads the
// group snapshot itself via `ref.watch(groupSnapshotProvider(groupId))`,
// so the screen no longer needs to pass `async` in. The peer-status
// toggle + leave are screen-level concerns; the header calls back via
// [onOpenPeerStatus] / [onLeave].
//
// The subtitle template, admin-pill, copy-invite timer (1600ms), clipboard
// call, and tooltip switch are byte-identical to the pre-refactor AppBar
// block (passes commits e93cb5d + 9cc0a93 review).

import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/chat_header_menu.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';

/// The GroupScreen AppBar header: the two-line title Column (group label +
/// subtitle) plus the `actions:` row (admin-pill, copy-invite, peer-status,
/// leave). Owns the copy-invite ephemeral state and reads the group
/// snapshot itself, so it is self-contained; the screen passes only the
/// `groupId` + the two screen-level callbacks.
///
/// ctor:
///   - [groupId] -- the group identity; the title fallback when the
///     snapshot has not resolved yet, and the family arg for the watch.
///   - [onOpenPeerStatus] -- screen toggles `_showPeerStatus = true`.
///   - [onLeave] -- screen's `_leave` (gateway.leave + nav back).
class GroupScreenHeader extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  const GroupScreenHeader({
    super.key,
    required this.groupId,
    required this.onOpenPeerStatus,
    required this.onLeave,
    required this.mobileSearchOpen,
    required this.onToggleMobileSearch,
    required this.filter,
    required this.onFilter,
  });

  final String groupId;
  final VoidCallback onOpenPeerStatus;
  final VoidCallback onLeave;
  // Mobile search panel open state + toggle -- the open state is owned by
  // the screen (mirrors React `useMobileSearchPanel` in ActiveChatHeader),
  // but the toggle button renders in this header's `actions:` row, so the
  // screen passes the current value + a toggle callback down.
  final bool mobileSearchOpen;
  final VoidCallback onToggleMobileSearch;
  // Conversation filter + onFilter -- the filter is owned by the screen
  // (the body's ConversationTools + the kebab's filter toggle both drive
  // it), so the screen passes the current value + a setter down, mirroring
  // the mobileSearchOpen/onToggleMobileSearch pair.
  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  ConsumerState<GroupScreenHeader> createState() => _GroupScreenHeaderState();
}

class _GroupScreenHeaderState extends ConsumerState<GroupScreenHeader> {
  // Copy-invite ephemeral state (React inviteCopied/inviteCopyTimer
  // ~L255-256); reverts after 1600ms; React's useEffect([inviteUri]) reset
  // is omitted (GroupScreen -- and therefore this header -- remounts per
  // groupId, so state resets on cross-group nav).
  bool _inviteCopied = false;
  Timer? _inviteCopyTimer;

  @override
  void dispose() {
    _inviteCopyTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyInvite(String? inviteUri) async {
    if (inviteUri == null) return;
    await Clipboard.setData(ClipboardData(text: inviteUri));
    if (!mounted) return;
    setState(() => _inviteCopied = true);
    _inviteCopyTimer?.cancel();
    _inviteCopyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _inviteCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(groupSnapshotProvider(widget.groupId));
    // React ActiveChatHeader `title` + `subtitle` (ActiveChatPanes.tsx
    // ~L305-313): title = the group label (or "Private group" fallback);
    // subtitle = is_admin ? `${adminBadge} · ` : ""
    //   + `${member_count} member${member_count === 1 ? "" : "s"} · MLS ${state}`.
// Flutter `AppBar` (3.44) has no `subtitle:` slot, so the subtitle
// renders as the second line of a two-line `title:` Column (the
// idiomatic Flutter AppBar-with-subtitle pattern). Admin prefix (with
// the " · " separator) only when admin; member count rendered via an
// ICU MessageFormat plural ([AppLocalizations.membersCount], typed int
// `count`) so the locale selects the correct form (English one/other;
// Russian one/few/many) -- this CORRECTS the Russian grammar that the
// prior naive binary plural (`memberCount == BigInt.one ? singular :
// plural`) broke ("2 участников" -> "2 участника"); then the
// " · MLS {state}" suffix via groupScreenMlsStateSuffix.
    return AppBar(
      toolbarHeight: chatHeaderHeight(context),
      titleTextStyle: chatTitleStyle(context),
      leading: railBackButton(context),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(async.maybeWhen(
            data: (group) => group.label ?? l.groupUntitled,
            orElse: () => widget.groupId,
          )),
          SizedBox(height: chatSubtitleGap(context)),
          Text(
            async.maybeWhen(
              data: (group) => _groupSubtitle(group, l),
              orElse: () => '',
            ),
            style: chatSubtitleStyle(context),
          ),
        ],
      ),
      actions: [
        // React `beforeSearchActions` slot (ActiveChatPanes.tsx ~L315-324):
        // the admin-pill badge (<span className="admin-pill
        // chat-desktop-only" title={adminBadge}><IconCrown size=14/>
        // <span>{adminBadge}</span></span>) shown only if is_admin. Placed
        // FIRST in `actions:` so it sits left of the peer-status + leave
        // IconButtons, mirroring React's beforeSearchActions position
        // (left of the search). `Icons.workspace_premium` is the closest
        // Material equivalent to lucide `IconCrown` (a crown medal) -- the
        // rail already uses the same icon for its admin crown
        // (group_rail_item.dart).
        if (async.maybeWhen(
          data: (group) => group.isAdmin,
          orElse: () => false,
        ))
          _AdminPill(label: l.groupAdminBadge),
        // React `beforeSearchActions` copy-invite button (~L327-337):
        // ghost icon button copying `invite_uri`, check ~1.6s then
        // revert; only when inviteUri != null; icon 14; tooltip done/invite.
        if (async.maybeWhen(
          data: (group) => group.inviteUri != null,
          orElse: () => false,
        ))
          IconButton(
            icon: Icon(_inviteCopied ? Icons.check : Icons.copy, size: 14),
            tooltip: _inviteCopied ? l.groupCopyInviteDone : l.groupCopyInvite,
            onPressed: () => _copyInvite(async.value?.inviteUri),
          ),
        // Mobile search toggle -- 1-1 with React `MobileSearchToggle`
        // (ActiveChatHeader.tsx L113-131), gated on the mobile breakpoint
        // (React `chat-mobile-only` class). Placed after the copy-invite
        // button (React `beforeSearchActions`) and before the peer-status +
        // leave buttons (React `afterSearchActions`), mirroring the React
        // header order `beforeSearchActions | MobileSearchToggle |
        // afterSearchActions`. The open state + toggle live in the screen;
        // this header only renders the button + forwards taps.
        if (isMobileBreakpoint(context))
          MobileSearchToggle(
            open: widget.mobileSearchOpen,
            onToggle: widget.onToggleMobileSearch,
            l: l,
          ),
        // Mobile kebab menu -- 1-1 with React `ChatHeaderMenu`
        // (ChatHeaderMenu.tsx) prepended with the filter toggle via
        // `conversationMenuActions` (ActiveChatHeader.tsx ~L155-170).
        // Self-gates to mobile; React places it last in
        // `chat-header-actions`. The group `menuActions` (ActiveChatPanes
        // ActiveGroupChat ~L252-271): Copy invite (only when inviteUri !=
        // null; label flips to "Invite copied" for 1600ms via the SAME
        // `_copyInvite` + `_inviteCopied` state the desktop copy-invite
        // IconButton uses -- the action list rebuilds on setState so the
        // label/icon flip), then Leave group (danger; onSelect ->
        // onClose -> widget.onLeave). Filter toggle FIRST
        // (attachments -> "All"/Icons.chat_bubble_outline -> onFilter(all);
        // else "Files"/Icons.attach_file -> onFilter(attachments)).
        ChatHeaderMenu(
          l: l,
          actions: [
            if (widget.filter == ConversationFilter.attachments)
              ChatHeaderMenuAction(
                label: l.chatFilterAll,
                icon: Icons.chat_bubble_outline,
                onSelect: () => widget.onFilter(ConversationFilter.all),
              )
            else
              ChatHeaderMenuAction(
                label: l.chatFilterAttachments,
                icon: Icons.attach_file,
                onSelect: () => widget.onFilter(ConversationFilter.attachments),
              ),
            if (async.maybeWhen(
              data: (group) => group.inviteUri != null,
              orElse: () => false,
            ))
              ChatHeaderMenuAction(
                label:
                    _inviteCopied ? l.groupCopyInviteDone : l.groupCopyInvite,
                icon: _inviteCopied ? Icons.check : Icons.copy,
                onSelect: () => _copyInvite(async.value?.inviteUri),
              ),
            ChatHeaderMenuAction(
              label: l.groupLeaveLabel,
              icon: Icons.logout,
              danger: true,
              onSelect: widget.onLeave,
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.electrical_services, size: 18),
          tooltip: l.openPeerStatus,
          onPressed: widget.onOpenPeerStatus,
        ),
        // React marks the leave button `chat-desktop-only` (ActiveChatPanes
        // ~L267-271); on mobile the kebab's "Leave group" item is the
        // entry point instead.
        if (!isMobileBreakpoint(context))
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.groupLeaveLabel,
            onPressed: widget.onLeave,
          ),
      ],
    );
  }
}

/// Builds the GroupScreen AppBar subtitle, 1-в-1 with React
/// `ActiveChatHeader.subtitle` (ActiveChatPanes.tsx ~L308-313):
///   is_admin ? `${adminBadge} · ` : ""
///   + `${member_count} member${member_count === 1 ? "" : "s"} · MLS ${state}`
/// Admin prefix (with the " · " separator) only when admin; the member
/// count rendered via an ICU MessageFormat plural
/// ([AppLocalizations.membersCount], typed int `count`) so the locale
/// selects the correct form (English one "1 member" / other "N members";
/// Russian one "1 участник" / few "2 участника" / many "5 участников").
/// This CORRECTS the prior naive binary plural (which selected a
/// separate singular key when `memberCount == BigInt.one`) that
/// mirrored React's inline ternary but was grammatically broken for
/// Russian (rendered "2 участников" instead of "2 участника"); the
/// former singular key was removed (the ICU `one` form now handles
/// the singular). Then the " · MLS {state}" suffix from
/// [AppLocalizations.groupScreenMlsStateSuffix].
String _groupSubtitle(GroupSnapshot group, AppLocalizations l) {
  final n = group.memberCount.toInt();
  final memberPart = l.membersCount(n);
  final adminPrefix = group.isAdmin ? '${l.groupAdminBadge} · ' : '';
  return '$adminPrefix$memberPart${l.groupScreenMlsStateSuffix(group.state)}';
}

/// Admin-pill badge for the GroupScreen AppBar `actions:` slot, 1-в-1 with
/// React's `beforeSearchActions` admin-pill (ActiveChatPanes.tsx ~L315-324):
/// `<span className="admin-pill chat-desktop-only" title={adminBadge}>
/// `<IconCrown size=14/><span>{adminBadge}</span></span>`. A small pill with
/// a crown icon + the "admin" label, wrapped in a [Tooltip] that mirrors
/// React's `title` attribute. `Icons.workspace_premium` is the closest
/// Material equivalent to lucide `IconCrown` (a crown medal) -- the rail
/// already uses the same icon for its admin crown (group_rail_item.dart).
class _AdminPill extends StatelessWidget {
  const _AdminPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium, size: 14),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
