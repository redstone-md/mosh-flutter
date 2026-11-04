import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';

import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind, ConversationRef;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/notifications_provider.dart'
    show
        flutterLocalNotificationsPluginProvider,
        moshNotificationDetails,
        notificationsReadyProvider;
import 'package:mosh/src/state/unread_providers.dart';
import 'package:mosh/src/state/window_focus_provider.dart';
import 'package:mosh/src/util/unread.dart';

/// The unread badges, keyed by [ConversationRef.key]. Each is the count the
/// core reports, except for the conversation on screen in a focused window.
/// A count that grows while the window is unfocused also raises an OS toast.
final unreadLifecycleProvider =
    NotifierProvider<_UnreadLifecycleNotifier, Map<String, int>>(
  _UnreadLifecycleNotifier.new,
);

class _UnreadLifecycleNotifier extends Notifier<Map<String, int>> {
  // The counts of the previous poll, so only growth raises a toast. Kept
  // across `build` re-runs because the Notifier instance is reused; the
  // first poll after launch is its baseline.
  Map<String, int> _lastSeen = {};

  // The exposed unread map, kept on the instance so `build` can return it
  // without a flicker while the async diff runs.
  Map<String, int> _unread = {};

  // Cancels stale async diff continuations.
  int _runToken = 0;

  @override
  Map<String, int> build() {
    // Watch the per-kind counts + the active key so a count change re-runs
    // `build` (and thus re-runs the diff). `.value` degrades to an empty
    // map while loading/error so the diff sees no conversations for that
    // slice. The watch order carries no meaning -- [_runDiff] fixes the
    // order the kinds are merged in (dm -> group -> channel).
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
    // while the focus check resolves.
    return _unread;
  }

  Future<void> _runDiff(
    int token,
    Map<String, int> dm,
    Map<String, int> channels,
    Map<String, int> groups,
    String? activeKey,
  ) async {
    final counts = <ConversationCount>[
      for (final entry in [
        ...dm.entries,
        ...groups.entries,
        ...channels.entries
      ])
        ConversationCount(id: entry.key, unread: entry.value),
    ];

    final focused = await ref.read(windowFocusProvider)() &&
        ref.read(androidAppAccessProvider)?.chatsInteractive != false;
    // A newer run superseded this one: drop it.
    if (token != _runToken) return;

    final diff = diffConversations(counts, _lastSeen, activeKey, !focused);
    _lastSeen = diff.nextLastSeen;

    _unread = {
      for (final conversation in counts)
        if (conversation.unread > 0 &&
            !(focused && conversation.id == activeKey))
          conversation.id: conversation.unread,
    };
    if (!focused) await _toast(diff.newMessages);
    state = _unread;
  }

  /// One OS toast per conversation whose count grew, while the window is
  /// unfocused and notifications are ready. The body comes from
  /// `notificationBody`.
  Future<void> _toast(List<NewMessages> grown) async {
    if (grown.isEmpty ||
        ref.read(androidWaitingOwnerProvider)?.attached == true ||
        !(ref.read(notificationsReadyProvider).value ?? false)) {
      return;
    }
    final plugin = ref.read(flutterLocalNotificationsPluginProvider);
    for (final message in grown) {
      // Android disclosure belongs to the native privacy-aware publisher;
      // this legacy fallback is always generic, including during a lock race.
      final body = ref.read(androidAppAccessProvider) == null
          ? notificationBody(message.id)
          : const NotificationBody(title: 'Mosh', body: 'New message');
      try {
        await plugin.show(
          id: message.id.hashCode.abs(),
          title: body.title,
          body: body.body,
          notificationDetails: moshNotificationDetails,
        );
      } catch (_) {
        // Notification host unavailable; the badge still updates.
      }
    }
  }
}
