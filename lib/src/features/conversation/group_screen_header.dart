// GroupScreen AppBar header. The AppBar skeleton (rail back button,
// search, details identity and action menu) lives in the shared
// ConversationAppBar; this header builds the group title/status and
// the invitation menu action, and owns
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
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_header_title.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';

/// The GroupScreen AppBar header: the two-line title Column (group label +
/// subtitle) plus the invitation menu action. Admin role appears once.
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
    final group = async.value;
    return ConversationAppBar(
      kind: ConversationKind.group,
      avatarName: group?.label ?? l.groupUntitled,
      title: ConversationHeaderTitle(
        name: group == null ? widget.groupId : group.label ?? l.groupUntitled,
        subtitle: group == null ? '' : _groupSubtitle(group, l),
      ),
      identityAction: FingerprintLock(
        fingerprint: group?.creatorFingerprint ?? '',
        hint: l.groupFingerprintHint,
      ),
      onOpenPeerStatus: widget.onOpenPeerStatus,
      onRequestLeave: widget.onLeave,
      filter: widget.filter,
      onFilter: widget.onFilter,
      mobileSearchOpen: widget.mobileSearchOpen,
      onToggleMobileSearch: widget.onToggleMobileSearch,
      leaveMenuLabel: l.groupLeaveLabel,
      leaveMenuIcon: Icons.logout,
      menuActions: [
        if (group?.inviteUri != null)
          ChatHeaderMenuAction(
            label: _inviteCopied ? l.groupCopyInviteDone : l.groupCopyInvite,
            icon: _inviteCopied ? Icons.check : Icons.copy,
            onSelect: () => _copyInvite(group?.inviteUri),
          ),
      ],
    );
  }
}

/// The role appears once, alongside membership and actual MLS state.
String _groupSubtitle(GroupSnapshot group, AppLocalizations l) {
  final memberPart = l.membersCount(group.memberCount.toInt());
  final adminPrefix = group.isAdmin ? '${l.groupAdminBadge}, ' : '';
  return '$adminPrefix$memberPart${l.groupScreenMlsStateSuffix(group.state)}';
}
