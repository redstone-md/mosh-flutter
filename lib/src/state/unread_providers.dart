// Unread-message counts, one provider for all three conversation kinds.
// [unreadCounts] derives a `Map<String,int>` of unread counts from one
// [ConversationList] -- keyed by [ConversationRef.key], the same
// `'dm:<sessionId>'` / `'channel:<name>'` / `'group:<groupId>'` shapes
// React's `useUnreadNotifications` uses for each conversation kind.
//
// The one branch the three kinds need lives in [unreadCounts]: a DM
// compares device names (a DM carries no per-message fingerprint, and there
// is only one peer, so the display-name comparison suffices), while a
// channel and a group compare fingerprints -- display names are not unique
// in a multi-party room, so a same-named peer must still count and a
// renamed self must not.
//
// Lifecycle: the provider derives counts from the current
// [conversationListProvider] snapshot ONLY. It is NOT the full poll-diff
// lifecycle from React's `unread.ts` (notifications, window-focus,
// `clearOnActive`, `diffConversations`, `lastSeen` persistence). That
// layering is `unread_lifecycle_provider.dart`'s job -- here the count is
// simply the number of not-own messages currently in each conversation.
//
// The visible `UnreadBadge` (sessions_screen.dart) hides when count<=0,
// shows "99+" past 99 -- mirroring React's `UnreadBadge` component.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/util/unread.dart';

/// The unread count of every conversation in [list], keyed by the
/// conversation's own key.
///
/// Pure + synchronous so the provider body and the unit tests share one
/// code path. A conversation with no not-own messages is present with a
/// count of 0, which is what lets a badge clear instead of vanish.
Map<String, int> unreadCounts(ConversationList list) {
  final counts = <String, int>{};
  switch (list) {
    case DmConversationList(:final snapshot):
      for (final session in snapshot.sessions) {
        final authors = session.messages
            .map((m) => MessageAuthor(
                  fromDevice: m.fromDevice,
                  fromFingerprint: null,
                ))
            .toList();
        counts[_keyOf(ConversationKind.dm, session.sessionId)] =
            countMessagesFromOthers(authors, session.displayName);
      }
    case ChannelConversationList(:final snapshot):
      for (final channel in snapshot.channels) {
        final authors = channel.messages
            .map((m) => MessageAuthor(
                  fromDevice: m.fromDevice,
                  fromFingerprint: m.fromFingerprint,
                ))
            .toList();
        counts[_keyOf(ConversationKind.channel, channel.name)] =
            countMessagesFromOthers(
          authors,
          channel.displayName,
          channel.deviceFingerprint,
        );
      }
    case GroupConversationList(:final snapshot):
      for (final group in snapshot.groups) {
        final authors = group.messages
            .map((m) => MessageAuthor(
                  fromDevice: m.fromDevice,
                  fromFingerprint: m.fromFingerprint,
                ))
            .toList();
        counts[_keyOf(ConversationKind.group, group.groupId)] =
            countMessagesFromOthers(
          authors,
          group.displayName,
          group.deviceFingerprint,
        );
      }
  }
  return counts;
}

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
