import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/features/conversation/conversation_chrome.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_header_title.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';

class GroupScreenHeader extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  const GroupScreenHeader({
    super.key,
    required this.chrome,
    required this.groupId,
  });

  final String groupId;

  final ConversationChrome chrome;

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
      chrome: widget.chrome,
      kind: ConversationKind.group,
      avatarName: group?.label ?? l.groupUntitled,
      title: ConversationHeaderTitle(
        name: group == null ? widget.groupId : group.label ?? l.groupUntitled,
        subtitle: group == null ? '' : _groupSubtitle(group, l),
        onOpenDetails: widget.chrome.onOpenPeerStatus,
        nameAction: FingerprintLock(
            fingerprint: group?.creatorFingerprint ?? '',
            hint: l.groupFingerprintHint,
            besideName: true),
      ),
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
