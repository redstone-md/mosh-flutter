// Unread-count provider for DM sessions. Derives a `Map<String,int>` of
// unread counts from the current `sessionListProvider` snapshot, keyed by
// `'dm:${session.sessionId}'` -- the same key shape React's
// `useUnreadNotifications` uses for 1:1 DM sessions.
//
// Scope (this atomic): DM sessions ONLY. Channels/groups will key on a
// fingerprint once those snapshots land; the counting primitive
// `countMessagesFromOthers` already supports a fingerprint argument, but
// the wiring is deferred until a channel/group list provider exists.
//
// Lifecycle: this provider derives counts from the current
// `sessionListProvider` snapshot ONLY. It is NOT the full poll-diff
// lifecycle from React's `unread.ts` (notifications, window-focus,
// `clearOnActive`, `diffConversations`, `lastSeen` persistence). That
// layering is a later atomic -- here the count shown is simply the number
// of not-own messages currently in each session (a reasonable first
// approximation; React's full unread-with-clearing layers on top of it).
//
// The visible `UnreadBadge` (sessions_screen.dart) hides when count<=0,
// shows "99+" past 99 -- mirroring React's `UnreadBadge` component.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
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
