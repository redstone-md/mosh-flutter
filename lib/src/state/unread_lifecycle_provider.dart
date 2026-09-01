// The unread-message OS-toast lifecycle, 1-1 port of React's
// `useUnreadNotifications` (mosh/src/features/private-dm/notifications/
// use-unread-notifications.ts). This is the atomic that the
// `unread_providers.dart` header deferred: it layers the poll-diff
// lifecycle (clearOnActive + window-focus toasts + `lastSeen`
// persistence) on top of the per-kind unread counts.
//
// The two regressions this fixes vs React:
//  1. The unread badge never cleared when a conversation was opened --
//     the raw count maps recompute the full not-own count every poll
//     regardless of which conversation is active. React clears the
//     active conversation's badge on window-focus (clearUnread(activeKey)
//     when focused). This provider exposes a `clearUnread` mutation +
//     clears the active key on a focused poll.
//  2. No OS toast fired on new messages in the background. React fires
//     one Tauri sendNotification per newly-grown conversation gated on
//     `!focused && notificationsReady`. This provider fires one
//     flutter_local_notifications `show` per diffed non-active
//     conversation when the window is unfocused + the gate is open.
//
// Shape: a non-autoDispose `Notifier<Map<String,int>>` so `lastSeen`
// (the poll-diff baseline) persists across count-provider rebuilds --
// the Notifier instance is reused by Riverpod across `build` re-runs,
// so the mutable instance field survives (mirrors React's `lastSeenRef`).
// `build` watches the per-kind counts + the active-conversation key,
// returns the current unread map (no flicker) and kicks off an async
// `_runDiff` continuation that awaits the focus seam, computes the
// diff, advances `lastSeen`, applies clearOnActive + newMessages, and
// fires the OS toasts. A `_runToken` cancels stale continuations when
// another watch fires before the focus check resolves (mirrors React's
// `cancelled` flag).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/notifications_provider.dart'
    show
        flutterLocalNotificationsPluginProvider,
        moshNotificationDetails,
        notificationsReadyProvider;
import 'package:mosh/src/state/unread_providers.dart';
import 'package:mosh/src/state/window_focus_provider.dart';
import 'package:mosh/src/util/unread.dart';

/// The unread-lifecycle provider. Exposes the `unread` map (keyed
/// `dm:<id>` / `channel:<name>` / `group:<id>`) consumed by the sessions
/// rail + the chat screens, and a `clearUnread(key)` mutation.
final unreadLifecycleProvider =
    NotifierProvider<_UnreadLifecycleNotifier, Map<String, int>>(
  _UnreadLifecycleNotifier.new,
);

class _UnreadLifecycleNotifier extends Notifier<Map<String, int>> {
  // Poll-diff baseline, 1-1 with React's `lastSeenRef.current`. Persists
  // across `build` re-runs because the Notifier instance is reused.
  Map<String, int> _lastSeen = {};

  // The exposed unread map, kept on the instance so `build` can return it
  // without a flicker while the async diff runs.
  Map<String, int> _unread = {};

  // Cancels stale async diff continuations (mirrors React's `cancelled`).
  int _runToken = 0;

  @override
  Map<String, int> build() {
    // Watch the per-kind counts + the active key so a count change re-runs
    // `build` (and thus re-runs the diff). `.value` degrades to an empty
    // map while loading/error so the diff sees no conversations for that
    // slice (matching React's empty-arrays-while-loading shape). The watch
    // order carries no meaning -- [_runDiff] fixes the order the kinds are
    // merged in (React's `counts[]`: dm -> group -> channel).
    final dm = ref.watch(unreadCountsProvider(ConversationKind.dm)).value ??
        const <String, int>{};
    final groups =
        ref.watch(unreadCountsProvider(ConversationKind.group)).value ??
            const <String, int>{};
    final channels =
        ref.watch(unreadCountsProvider(ConversationKind.channel)).value ??
            const <String, int>{};
    final activeKey = ref.watch(activeConversationKeyProvider);

    // Kick off the async diff (focus check is awaited). Each run captures
    // its own token; before applying state it checks it is still latest so
    // a fast follow-up watch (DM + channel changing together) does not
    // apply a stale diff on top of a newer one.
    final token = ++_runToken;
    _runDiff(token, dm, channels, groups, activeKey);

    // Return the current unread immediately so the UI does not flicker
    // while the focus check resolves (React renders with the prior unread
    // until the effect's async IIFE updates it).
    return _unread;
  }

  Future<void> _runDiff(
    int token,
    Map<String, int> dm,
    Map<String, int> channels,
    Map<String, int> groups,
    String? activeKey,
  ) async {
    // Build the combined counts list, 1-1 with React's `counts[]` (dm +
    // group + channel, keyed by the same shapes the count maps use).
    final counts = <ConversationCount>[
      for (final entry in dm.entries)
        ConversationCount(id: entry.key, messageCount: entry.value),
      for (final entry in groups.entries)
        ConversationCount(id: entry.key, messageCount: entry.value),
      for (final entry in channels.entries)
        ConversationCount(id: entry.key, messageCount: entry.value),
    ];

    final focused = await ref.read(windowFocusProvider)();
    // A newer run superseded this one: drop it (React's `cancelled`).
    if (token != _runToken) return;

    final diff = diffConversations(counts, _lastSeen, activeKey, !focused);
    _lastSeen = diff.nextLastSeen;

    // clearOnActive: if focused + an active key, clear its unread (React's
    // `if (focused && activeKey) clearUnread(activeKey)`).
    if (focused && activeKey != null) {
      if (_unread.containsKey(activeKey)) {
        _unread = {..._unread}..remove(activeKey);
      }
    }

    if (diff.newMessages.isEmpty) {
      state = _unread;
      return;
    }

    // Apply newMessages to the unread map, skipping the active conversation
    // when focused (React's `if (id === activeKey && focused) continue`).
    var next = _unread;
    var mutated = false;
    for (final message in diff.newMessages) {
      if (message.id == activeKey && focused) continue;
      if (!mutated) {
        next = {..._unread};
        mutated = true;
      }
      next[message.id] = (next[message.id] ?? 0) + message.delta;
    }
    if (mutated) _unread = next;

    // OS toasts: one per diffed conversation when unfocused + the gate is
    // open (React's `if (!focused && notifyReadyRef.current)`). The body
    // comes from the existing `notificationBody` (mirrors React's
    // sendNotification(notificationBody(id))).
    if (!focused) {
      final ready = ref.read(notificationsReadyProvider).value ?? false;
      if (ready) {
        final plugin = ref.read(flutterLocalNotificationsPluginProvider);
        for (final message in diff.newMessages) {
          final body = notificationBody(message.id);
          try {
            await plugin.show(
              id: message.id.hashCode.abs(),
              title: body.title,
              body: body.body,
              notificationDetails: moshNotificationDetails,
            );
          } catch (_) {
            // Notification host unavailable; the badge still updates
            // (mirrors React's catch around sendNotification).
          }
        }
      }
    }

    state = _unread;
  }

  /// Removes `key` from the exposed unread map, 1-1 with React's
  /// `clearUnread`. Called by the sessions rail on select + the chat
  /// screens on open so the badge clears the moment a conversation is
  /// opened (not waiting for the next poll).
  void clearUnread(String key) {
    if (!_unread.containsKey(key)) return;
    _unread = {..._unread}..remove(key);
    state = _unread;
  }
}
