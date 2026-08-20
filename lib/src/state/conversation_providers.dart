/// One snapshot provider for every conversation kind.
///
/// It does not poll. It watches the kind provider the app already has and
/// maps the result into [ConversationSnapshot]. That keeps one poll per
/// conversation and keeps `ref.invalidate(channelSnapshotProvider(name))` and
/// friends working exactly as before: the kind provider refreshes, and this
/// one follows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/channel_group_providers.dart'
    show channelSnapshotProvider, groupSnapshotProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;

/// One conversation's snapshot, keyed by its target. Two targets of the same
/// kind and id are equal, so the family hands back the same entry.
final conversationSnapshotProvider =
    FutureProvider.family<ConversationSnapshot, AnyConversationTarget>(
  (ref, target) async => switch (target) {
    DmTarget() => DmConversation(
        target,
        await ref.watch(activeSessionProvider(target.id).future),
      ),
    ChannelTarget() => ChannelConversation(
        target,
        await ref.watch(channelSnapshotProvider(target.id).future),
      ),
    GroupTarget() => GroupConversation(
        target,
        await ref.watch(groupSnapshotProvider(target.id).future),
      ),
  },
);
