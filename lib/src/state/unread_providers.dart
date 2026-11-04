import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/conversation_providers.dart';

/// The unread count of every conversation in [list], keyed by the
/// conversation's own key.
///
/// The core keeps what the user has seen in its encrypted store and reports
/// the rest on each snapshot, so these counts survive a restart. A snapshot
/// without that report counts as nothing unread.
Map<String, int> unreadCounts(ConversationList list) => switch (list) {
      DmConversationList(:final snapshot) => {
          for (final session in snapshot.sessions)
            _keyOf(ConversationKind.dm, session.sessionId):
                session.unread?.count ?? 0,
        },
      ChannelConversationList(:final snapshot) => {
          for (final channel in snapshot.channels)
            _keyOf(ConversationKind.channel, channel.name):
                channel.unread?.count ?? 0,
        },
      GroupConversationList(:final snapshot) => {
          for (final group in snapshot.groups)
            _keyOf(ConversationKind.group, group.groupId):
                group.unread?.count ?? 0,
        },
    };

/// The key one conversation is counted under. [ConversationRef] owns the
/// grammar, so no key literal is written here.
String _keyOf(ConversationKind kind, String id) =>
    ConversationRef(kind: kind, id: id).key;

/// Server state: the unread counts of one conversation kind, keyed by
/// [ConversationRef.key].
///
/// Watches that kind's list so it recomputes whenever the list refreshes
/// (post-send, post-invite). On loading/error the badge is absent -- the
/// provider surfaces AsyncValue.error/loading so the sessions list degrades
/// cleanly; the badge's null-guard handles both.
final unreadCountsProvider =
    FutureProvider.family<Map<String, int>, ConversationKind>(
  (ref, kind) async =>
      unreadCounts(await ref.watch(conversationListProvider(kind).future)),
);
