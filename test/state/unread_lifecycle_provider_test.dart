// Tests for `unreadLifecycleProvider` -- the badges the core's persisted
// unread counts produce, hidden for the conversation on screen, plus the
// window-focus OS toasts fired when a count grows. Re-seeding the bridge's
// lists with new counts and refreshing them drives each poll.
//
// Seams overridden (mirrors the notifications seam convention):
//  - `bridgeFacadeProvider` -> `ScriptableBridge` (mutable list snapshots).
//  - `windowFocusProvider` -> a controllable `Future<bool> Function()` so
//    the focus check is deterministic without a window_manager method-
//    channel mock (the lifecycle reads this seam, not windowManager).
//  - `flutterLocalNotificationsPluginProvider` -> a recording fake whose
//    `show` records (id, title, body).
//  - `notificationsReadyProvider` -> `AsyncValue.data(true/false)` to open
//    or close the toast gate without running the real plugin init.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scriptable_bridge.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/conversation/read_marks.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/notifications_provider.dart';
import 'package:mosh/src/state/unread_lifecycle_provider.dart';
import 'package:mosh/src/state/unread_providers.dart';
import 'package:mosh/src/state/window_focus_provider.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';

part 'unread_lifecycle_provider_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('unreadLifecycleProvider', () {
    test('the first poll after a restart shows the unread counts the core kept',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.gateway.seedSessions([_dmSession(sessionId: 'a', unread: 2)]);
      h.gateway.seedChannels([_channel(name: 'general', unread: 1)]);
      h.gateway.seedGroups([_group(groupId: 'quiet')]);

      await _poll(h.container);

      expect(h.container.read(unreadLifecycleProvider),
          {'dm:a': 2, 'channel:general': 1});
      expect(h.notifications.shows, isEmpty,
          reason: 'what was kept across a restart is not news to toast');
    });

    test('locked Android keeps unread messages and hides channel details',
        () async {
      final access = AndroidAppAccess();
      addTearDown(access.dispose);
      final h = _Harness(appAccess: access);
      addTearDown(h.container.dispose);
      h.container
          .read(activeConversationKeyProvider.notifier)
          .set('channel:private-project');
      for (final count in [1, 2]) {
        h.gateway
            .seedChannels([_channel(name: 'private-project', unread: count)]);
        await _poll(h.container);
      }
      expect(
          h.container.read(unreadLifecycleProvider)['channel:private-project'],
          2);
      final show = h.notifications.shows.single;
      expect(show.title, 'Mosh');
      expect(show.body, 'New message');
      expect(show.payload, isNull);
      expect(show.details?.android?.ticker, isNull);
    });

    test('the conversation on screen in a focused window shows no badge',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.container.read(activeConversationKeyProvider.notifier).set('dm:a');
      h.gateway.seedSessions([_dmSession(sessionId: 'a', unread: 1)]);
      h.gateway.seedChannels([_channel(name: 'general', unread: 1)]);
      await _poll(h.container);
      h.gateway.seedSessions([_dmSession(sessionId: 'a', unread: 2)]);
      h.gateway.seedChannels([_channel(name: 'general', unread: 2)]);
      await _poll(h.container);

      expect(h.container.read(unreadLifecycleProvider), {'channel:general': 2});
      expect(h.notifications.shows, isEmpty);
    });

    test('a badge clears once the core reports the conversation read',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.gateway.seedChannels([_channel(name: 'general', unread: 3)]);
      await _poll(h.container);
      h.gateway.seedChannels([_channel(name: 'general')]);
      await _poll(h.container);

      expect(h.container.read(unreadLifecycleProvider), isEmpty);
    });

    test(
        'a grown count in an unfocused window fires one toast per grown '
        'conversation with notificationBody text', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.setFocus(false);
      h.container.read(activeConversationKeyProvider.notifier).set('dm:a');
      h.gateway.seedSessions([_dmSession(sessionId: 'a', unread: 1)]);
      h.gateway.seedChannels([_channel(name: 'general', unread: 1)]);
      await _poll(h.container);
      h.gateway.seedChannels([_channel(name: 'general', unread: 2)]);
      await _poll(h.container);

      final show = h.notifications.shows.single;
      expect(show.title, 'Mosh');
      expect(show.body, '#general - new message');
      expect(show.details?.android?.channelId, 'mosh_notifications');
      expect(show.details?.android?.channelName, 'Mosh notifications');
    });

    test('no toast fires when the window is focused or notifications are off',
        () async {
      for (final (focused, ready) in [(true, true), (false, false)]) {
        final h = _Harness(notificationsReady: ready);
        addTearDown(h.container.dispose);
        h.setFocus(focused);
        for (final count in [1, 2]) {
          h.gateway.seedChannels([_channel(name: 'general', unread: count)]);
          await _poll(h.container);
        }
        expect(h.notifications.shows, isEmpty);
        expect(h.container.read(unreadLifecycleProvider)['channel:general'], 2);
      }
    });

    test('a conversation appearing mid-session shows its badge without a toast',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.setFocus(false);
      await _poll(h.container);
      h.gateway.seedGroups([_group(groupId: 'g1', unread: 2)]);
      await _poll(h.container);

      expect(h.container.read(unreadLifecycleProvider), {'group:g1': 2});
      expect(h.notifications.shows, isEmpty);
    });
  });
}
