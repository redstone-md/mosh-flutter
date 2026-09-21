// GroupScreen AppBar header. The AppBar skeleton (rail back button,
// mobile search toggle, kebab, peer-status, desktop leave) lives in the
// shared ConversationAppBar; this header only builds the group title
// (label + lock + subtitle), the admin-pill + copy-invite buttons, and
// the copy-invite ephemeral state (`_inviteCopied` + the 1600ms revert).
//
// Reads the group snapshot itself via `ref.watch(groupSnapshotProvider(
// groupId))`, so the screen passes only the `groupId` + the two
// screen-level callbacks ([onOpenPeerStatus] / [onLeave]).

import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';

/// The GroupScreen AppBar header: the two-line title Column (group label +
/// subtitle) plus the group-specific actions (admin-pill, copy-invite).
/// Owns the copy-invite ephemeral state and reads the group snapshot
/// itself, so it is self-contained.
///
/// ctor:
///   - [groupId] -- the group identity; the title fallback when the
///     snapshot has not resolved yet, and the family arg for the watch.
///   - [onOpenPeerStatus] -- screen toggles `_showPeerStatus = true`.
///   - [onLeave] -- screen's `_leave` (gateway.leave + nav back).
///   - [mobileSearchOpen] + [onToggleMobileSearch] -- the mobile search
///     panel open state, owned by the screen; forwarded to the shared
///     ConversationAppBar.
///   - [filter] + [onFilter] -- the conversation filter, owned by the
///     screen; forwarded to the shared kebab's filter toggle.
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
  final bool mobileSearchOpen;
  final VoidCallback onToggleMobileSearch;
  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  ConsumerState<GroupScreenHeader> createState() => _GroupScreenHeaderState();
}

class _GroupScreenHeaderState extends ConsumerState<GroupScreenHeader> {
  // Copy-invite ephemeral state; reverts after 1600ms. No inviteUri-change
  // reset is needed (GroupScreen -- and therefore this header -- remounts
  // per groupId, so state resets on cross-group nav).
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
    final hasInvite = async.maybeWhen(
      data: (group) => group.inviteUri != null,
      orElse: () => false,
    );
    // Flutter `AppBar` has no `subtitle:` slot, so the subtitle renders as
    // the second line of a two-line `title:` Column.
    return ConversationAppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Group label with the fingerprint lock beside it. The lock
          // shows the group's `creator_fingerprint` -- the same value
          // every member reads -- and renders nothing while the snapshot
          // has not resolved or the fingerprint is empty.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(async.maybeWhen(
                  data: (group) => group.label ?? l.groupUntitled,
                  orElse: () => widget.groupId,
                )),
              ),
              FingerprintLock(
                fingerprint: async.maybeWhen(
                  data: (group) => group.creatorFingerprint,
                  orElse: () => '',
                ),
                hint: l.groupFingerprintHint,
              ),
            ],
          ),
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
      onOpenPeerStatus: widget.onOpenPeerStatus,
      onRequestLeave: widget.onLeave,
      filter: widget.filter,
      onFilter: widget.onFilter,
      mobileSearchOpen: widget.mobileSearchOpen,
      onToggleMobileSearch: widget.onToggleMobileSearch,
      leaveMenuLabel: l.groupLeaveLabel,
      leaveMenuIcon: Icons.logout,
      desktopLeaveIcon: const Icon(Icons.logout),
      desktopLeaveTooltip: l.groupLeaveLabel,
      leadingActions: [
        // The admin-pill badge, shown only if is_admin. `Icons.
        // workspace_premium` matches the admin crown the rail uses.
        if (async.maybeWhen(
          data: (group) => group.isAdmin,
          orElse: () => false,
        ))
          _AdminPill(label: l.groupAdminBadge),
        // Copy-invite ghost icon button: copies `invite_uri`, shows a
        // check ~1.6s then reverts; only when inviteUri != null.
        if (hasInvite)
          IconButton(
            icon: Icon(_inviteCopied ? Icons.check : Icons.copy, size: 14),
            tooltip: _inviteCopied ? l.groupCopyInviteDone : l.groupCopyInvite,
            onPressed: () => _copyInvite(async.value?.inviteUri),
          ),
      ],
      menuActions: [
        // Kebab copy-invite (only when inviteUri != null; label flips to
        // "Invite copied" for 1600ms via the SAME `_copyInvite` +
        // `_inviteCopied` state the desktop IconButton uses).
        if (hasInvite)
          ChatHeaderMenuAction(
            label: _inviteCopied ? l.groupCopyInviteDone : l.groupCopyInvite,
            icon: _inviteCopied ? Icons.check : Icons.copy,
            onSelect: () => _copyInvite(async.value?.inviteUri),
          ),
      ],
    );
  }
}

/// Builds the GroupScreen AppBar subtitle: admin prefix (with the " · "
/// separator) only when admin, then the member count, then the
/// " · MLS {state}" suffix. The member count renders via an ICU
/// MessageFormat plural ([AppLocalizations.membersCount]) so the locale
/// selects the correct form (English one "1 member" / other "N members";
/// Russian one "1 участник" / few "2 участника" / many "5 участников").
String _groupSubtitle(GroupSnapshot group, AppLocalizations l) {
  final n = group.memberCount.toInt();
  final memberPart = l.membersCount(n);
  final adminPrefix = group.isAdmin ? '${l.groupAdminBadge} · ' : '';
  return '$adminPrefix$memberPart${l.groupScreenMlsStateSuffix(group.state)}';
}

/// Admin-pill badge for the GroupScreen AppBar `actions:` slot: a small
/// pill with a crown icon + the "admin" label, wrapped in a [Tooltip].
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
