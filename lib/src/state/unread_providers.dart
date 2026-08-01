// Unread-count providers for DM sessions, channels, and groups. Derive
// `Map<String,int>` maps of unread counts from the current
// `sessionListProvider` / `channelListProvider` / `groupListProvider`
// snapshots -- keyed `'dm:<sessionId>'` / `'channel:<name>'` /
// `'group:<groupId>'`, the same key shapes React's
// `useUnreadNotifications` uses for each conversation kind.
//
// Scope (this atomic): DM sessions, channels, and groups. DMs key on
// `'dm:${session.sessionId}'` and carry no fingerprint (2-party, so the
// display-name comparison suffices). Channels/groups now key on a
// fingerprint (the channel/group list providers landed in b750a87 +
// 42f0513): channels key `'channel:<name>'`, groups key `'group:<groupId>'`,
// and identity is compared by `fromFingerprint` against the local
// `deviceFingerprint` -- display names are not unique in multi-party rooms,
// so a same-named peer must still count and a renamed self must not. This is
// the 1-в-1 mirror of React's `useUnreadNotifications` channel/group
// branches.
//
// Lifecycle: these providers derive counts from the current
// `sessionListProvider` / `channelListProvider` / `groupListProvider`
// snapshots ONLY. They are NOT the full poll-diff
// lifecycle from React's `unread.ts` (notifications, window-focus,
// `clearOnActive`, `diffConversations`, `lastSeen` persistence). That
// layering is a later atomic -- here the count shown is simply the number
// of not-own messages currently in each session/channel/group (a
// reasonable first
// approximation; React's full unread-with-clearing layers on top of it).
//
// The visible `UnreadBadge` (sessions_screen.dart) hides when count<=0,
// shows "99+" past 99 -- mirroring React's `UnreadBadge` component.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/util/unread.dart';

/// Builds the per-DM unread map from a resolved `SessionListSnapshot`.
///
/// Pure + synchronous so the provider body and unit tests share one code
/// path. DM `ChatMessage`s carry no fingerprint, so the adapter passes
/// `fromFingerprint: null` -- matching React's DM branch which falls back
/// to the display-name comparison inside `countMessagesFromOthers`.
Map<String, int> unreadDmCounts(SessionListSnapshot snapshot) {
  final counts = <String, int>{};
  for (final session in snapshot.sessions) {
    final authors = session.messages
        .map((m) => MessageAuthor(fromDevice: m.fromDevice, fromFingerprint: null))
        .toList();
    final count = countMessagesFromOthers(authors, session.displayName);
    counts['dm:${session.sessionId}'] = count;
  }
  return counts;
}

/// Builds the per-channel unread map from a resolved `ChannelListSnapshot`.
///
/// Pure + synchronous, mirroring [unreadDmCounts]. Channels are multi-party,
/// so identity is by fingerprint: each `ChannelMessage` carries a non-null
/// `fromFingerprint` and `countMessagesFromOthers` is given the channel's
/// `deviceFingerprint` as `ownFingerprint`. Keys `'channel:<name>'`,
/// matching React's channel branch. A same-named peer still counts; a
/// renamed self does not.
Map<String, int> unreadChannelCounts(ChannelListSnapshot snapshot) {
  final counts = <String, int>{};
  for (final channel in snapshot.channels) {
    final authors = channel.messages
        .map((m) => MessageAuthor(
              fromDevice: m.fromDevice,
              fromFingerprint: m.fromFingerprint,
            ))
        .toList();
    final count = countMessagesFromOthers(
        authors, channel.displayName, channel.deviceFingerprint);
    counts['channel:${channel.name}'] = count;
  }
  return counts;
}

/// Builds the per-group unread map from a resolved `GroupListSnapshot`.
///
/// Pure + synchronous, mirroring [unreadDmCounts] / [unreadChannelCounts].
/// Groups are multi-party, so identity is by fingerprint: each `GroupMessage`
/// carries a non-null `fromFingerprint` and `countMessagesFromOthers` is
/// given the group's `deviceFingerprint` as `ownFingerprint`. Keys
/// `'group:<groupId>'`, matching React's group branch.
Map<String, int> unreadGroupCounts(GroupListSnapshot snapshot) {
  final counts = <String, int>{};
  for (final group in snapshot.groups) {
    final authors = group.messages
        .map((m) => MessageAuthor(
              fromDevice: m.fromDevice,
              fromFingerprint: m.fromFingerprint,
            ))
        .toList();
    final count = countMessagesFromOthers(
        authors, group.displayName, group.deviceFingerprint);
    counts['group:${group.groupId}'] = count;
  }
  return counts;
}

/// Server state: per-DM unread-message counts, keyed `'dm:<sessionId>'`.
///
/// Watches `sessionListProvider` so it recomputes whenever the list
/// refreshes (post-send, post-invite). On loading/error the badge is
/// absent -- the provider surfaces AsyncValue.error/loading so the
/// sessions list degrades cleanly; the badge's null-guard handles both.
final unreadDmCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  // `.future` on the provider resolves to the underlying AsyncNotifier
  // value (data) or throws on error -- surfaced to listeners by this
  // FutureProvider; loading re-runs the watch on the next rebuild.
  final snapshot = await ref.watch(sessionListProvider.future);
  return unreadDmCounts(snapshot);
});

/// Server state: per-channel unread-message counts, keyed `'channel:<name>'`.
///
/// Mirrors [unreadDmCountsProvider] 1:1 but against `channelListProvider`.
/// On loading/error the `.value` degrade in the sessions screen leaves the
/// map empty so channel badges stay absent (same null-guard path as DMs).
final unreadChannelCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final snapshot = await ref.watch(channelListProvider.future);
  return unreadChannelCounts(snapshot);
});

/// Server state: per-group unread-message counts, keyed `'group:<groupId>'`.
///
/// Mirrors [unreadDmCountsProvider] / [unreadChannelCountsProvider] 1:1 but
/// against `groupListProvider`. Same `.value` degrade as the others.
final unreadGroupCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final snapshot = await ref.watch(groupListProvider.future);
  return unreadGroupCounts(snapshot);
});
