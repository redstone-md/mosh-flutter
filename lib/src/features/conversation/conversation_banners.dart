import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_notice_preferences.dart';
import 'package:mosh/src/features/conversation/dismissible_conversation_notice.dart';
import 'package:mosh/src/features/conversation/group_rejoin_needed_error.dart';
import 'package:mosh/src/features/org/org_add_missing_banner.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show feedPadding;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/shared/mosh_notice.dart';
import 'dm_revocation_banner.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/org_providers.dart' show orgAddPromptProvider;
import 'package:mosh/src/rust/conversation/recovery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show DmHistorySyncState;

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
      ConversationKind.dm => Column(mainAxisSize: MainAxisSize.min, children: [
          DmRevocationBanner(
              state: loaded is DmConversation
                  ? loaded.source.deviceRevocation
                  : null),
          if (loaded is DmConversation && !loaded.revoked)
            _historyBanner(l, _dmHistoryState(loaded.source.historySync)),
        ]),
      ConversationKind.channel => _channelNotices(
          l, loaded is ChannelConversation ? loaded.source.historySync : null),
      ConversationKind.group => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DismissibleConversationNotice(
              kind: ConversationNoticeKind.encryptedGroup,
              icon: MoshIcons.lock,
              title: l.groupNoticeTitle,
              body: l.groupNoticeBody,
              tone: MoshNoticeTone.secure,
            ),
            if (loaded is GroupConversation && loaded.source.needsRejoin)
              FeedBanner(GroupRejoinNeededError(
                title: l.orgRejoinNeededTitle,
                body: l.orgRejoinNeededBody,
              )),
            _OrgAddMissing(groupId: target.id, l: l),
          ],
        ),
    };
  }
}

HistorySyncState? _dmHistoryState(DmHistorySyncState? state) => switch (state) {
      DmHistorySyncState.waitingForSource => HistorySyncState.waitingForSource,
      DmHistorySyncState.importing => HistorySyncState.importing,
      DmHistorySyncState.complete => HistorySyncState.complete,
      null => null,
    };

Widget _channelNotices(AppLocalizations l, HistorySync? status) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DismissibleConversationNotice(
          kind: ConversationNoticeKind.publicChannel,
          icon: MoshIcons.tag,
          title: l.channelNoticeTitle,
          body: l.channelNoticeBody,
          tone: MoshNoticeTone.open,
        ),
        _historyBanner(l, status?.state),
      ],
    );

Widget _historyBanner(AppLocalizations l, HistorySyncState? state) {
  final copy = switch (state) {
    HistorySyncState.waitingForSource => (
        l.dmHistoryWaitingTitle,
        l.dmHistoryWaitingBody
      ),
    HistorySyncState.importing => (
        l.dmHistoryImportingTitle,
        l.dmHistoryImportingBody
      ),
    HistorySyncState.complete || null => null,
  };
  if (copy == null) return const SizedBox.shrink();
  return FeedBanner(MoshNotice(
    tone: MoshNoticeTone.open,
    icon: MoshIcons.history,
    title: copy.$1,
    detail: copy.$2,
  ));
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
    return FeedBanner(OrgAddMissingBanner(
      count: prompt.count,
      busy: prompt.busy,
      onAdd: () => ref
          .read(conversationControllerProvider(GroupTarget(groupId)).notifier)
          .inviteMembers(prompt),
      missingOne: l.orgMissingOne,
      missingMany: l.orgMissingMany,
      addLabel: l.orgAddMissing,
    ));
  }
}

/// A banner where it stands in a conversation: above the feed, set in as far
/// as the feed's own content.
class FeedBanner extends StatelessWidget {
  const FeedBanner(this.banner, {super.key});

  final Widget banner;

  @override
  Widget build(BuildContext context) => Padding(
        padding: feedPadding(compact: isMobileBreakpoint(context))
            .copyWith(top: MoshSpace.s2, bottom: 0),
        child: banner,
      );
}
