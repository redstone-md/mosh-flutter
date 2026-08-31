/// The banners that sit between the header and the message list.
///
/// Which ones show follows the kind: a DM has none, a channel says its
/// messages are public, and a group says they are encrypted and can add a
/// rejoin warning and an "add the missing org members" prompt.
///
/// The notice comes from the target, not the snapshot, so it is there from
/// the first frame and stays if a read fails. Only the group's rejoin
/// warning waits for the snapshot, because only the snapshot knows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/group_rejoin_needed_error.dart';
import 'package:mosh/src/features/org/org_add_missing_banner.dart';
import 'package:mosh/src/features/shared/crypto_notice_banner.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/org_providers.dart' show orgAddPromptProvider;

/// The tint on the channel notice: the same info blue the web app used.
const Color _channelNoticeAccent = Color(0xFF6CB7E8);

/// The tint on the group notice: moss green.
const Color _groupNoticeAccent = Color(0xFFB7D84A);

class ConversationBanners extends StatelessWidget {
  const ConversationBanners({
    super.key,
    required this.target,
    required this.snapshot,
  });

  final AnyConversationTarget target;

  /// The conversation, or null while it is still loading. A banner that
  /// depends on it stays hidden until it arrives.
  final ConversationSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // A local, so the type check below promotes it.
    final loaded = snapshot;
    return switch (target.kind) {
      ConversationKind.dm => const SizedBox.shrink(),
      ConversationKind.channel => CryptoNoticeBanner(
          icon: Icons.tag,
          title: l.channelNoticeTitle,
          body: l.channelNoticeBody,
          accent: _channelNoticeAccent,
        ),
      ConversationKind.group => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CryptoNoticeBanner(
              icon: Icons.lock,
              title: l.groupNoticeTitle,
              body: l.groupNoticeBody,
              accent: _groupNoticeAccent,
            ),
            if (loaded is GroupConversation && loaded.source.needsRejoin)
              GroupRejoinNeededError(
                title: l.orgRejoinNeededTitle,
                body: l.orgRejoinNeededBody,
              ),
            _OrgAddMissing(groupId: target.id, l: l),
          ],
        ),
    };
  }
}

/// Offers an org admin the one tap that adds the org members who are not in
/// this group yet. Renders nothing when there is no one to add.
class _OrgAddMissing extends ConsumerWidget {
  const _OrgAddMissing({required this.groupId, required this.l});

  final String groupId;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompt = ref.watch(orgAddPromptProvider(groupId));
    if (prompt == null || prompt.count == 0) return const SizedBox.shrink();
    return OrgAddMissingBanner(
      count: prompt.count,
      busy: prompt.busy,
      onAdd: () => ref
          .read(conversationControllerProvider(GroupTarget(groupId)).notifier)
          .inviteMembers(prompt),
      missingOne: l.orgMissingOne,
      missingMany: l.orgMissingMany,
      addLabel: l.orgAddMissing,
    );
  }
}
