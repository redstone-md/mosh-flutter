// Tests for `unreadLifecycleProvider` -- the unread lifecycle (clear on
// active + window-focus OS toasts + lastSeen poll-diff). The lifecycle
// watches the per-kind unread counts (one `unreadCountsProvider` entry per
// kind) + activeConversationKeyProvider, so re-seeding the bridge's lists
// drives growth by swapping its list snapshots and refreshing the list
// entries.
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

part 'unread_lifecycle_provider_support.dart';

void main() {
  group('unreadLifecycleProvider', () {
    test(
        'case 1: the first poll seeds lastSeen and fires no notification '
        'and leaves the unread map empty (first-seen never reports)', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      // Seed a DM with one peer message + a channel with one peer message.
      h.gateway.seedSessions([
        _dmSession(
            sessionId: 'a', displayName: 'me', messages: [_dmMsg('peer')]),
      ]);
      h.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [_channelMsg('peer', 'peerfp')],
        ),
      ]);

      await _poll(h.container);

      expect(h.container.read(unreadLifecycleProvider), isEmpty);
      expect(h.notifications.shows, isEmpty);
    });

    test(
        'case 2: a second poll with grown counts + focused + active key '
        'clears the active conversation badge and fires no toast', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.setFocus(true);
      // Mark 'dm:a' as the active conversation (mirrors the chat screen
      // setting activeConversationKey on open).
      h.container.read(activeConversationKeyProvider.notifier).set('dm:a');
      // First poll: seed lastSeen (dm:a=1, channel:general=1).
      h.gateway.seedSessions([
        _dmSession(
            sessionId: 'a', displayName: 'me', messages: [_dmMsg('peer')]),
      ]);
      h.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [_channelMsg('peer', 'peerfp')],
        ),
      ]);
      await _poll(h.container);

      // Second poll: both grow by one peer message.
      h.gateway.seedSessions([
        _dmSession(
            sessionId: 'a',
            displayName: 'me',
            messages: [_dmMsg('peer'), _dmMsg('peer')]),
      ]);
      h.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [
            _channelMsg('peer', 'peerfp'),
            _channelMsg('peer', 'peerfp')
          ],
        ),
      ]);
      await _poll(h.container);

      final unread = h.container.read(unreadLifecycleProvider);
      // The active DM's badge is cleared (clearOnActive); the channel grew
      // and is non-active, so its unread delta applies.
      expect(unread['dm:a'], isNull);
      expect(unread['channel:general'], 1);
      expect(h.notifications.shows, isEmpty);
    });

    test(
        'case 3: the same growth with the window unfocused fires one toast '
        'per diffed non-active conversation with notificationBody text',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.setFocus(false);
      // 'dm:a' is active but does NOT grow this poll, so every diffed
      // conversation is non-active (the toast loop fires one toast per
      // grown conversation; with dm:a stable it is not in the diff).
      h.container.read(activeConversationKeyProvider.notifier).set('dm:a');
      // First poll: seed lastSeen (dm:a=1, channel:general=1).
      h.gateway.seedSessions([
        _dmSession(
            sessionId: 'a', displayName: 'me', messages: [_dmMsg('peer')]),
      ]);
      h.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [_channelMsg('peer', 'peerfp')],
        ),
      ]);
      await _poll(h.container);

      // Second poll: only the channel grows (dm:a stays at 1).
      h.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [
            _channelMsg('peer', 'peerfp'),
            _channelMsg('peer', 'peerfp')
          ],
        ),
      ]);
      await _poll(h.container);

      // One toast for the non-active channel; dm:a did not grow so no toast
      // for it. Body uses notificationBody('channel:general') text.
      expect(h.notifications.shows.length, 1);
      final show = h.notifications.shows.single;
      expect(show.title, 'Mosh');
      expect(show.body, '#general - new message');
      expect(show.details?.android?.channelId, 'mosh_notifications');
      expect(show.details?.android?.channelName, 'Mosh notifications');
    });

    test(
        'case 4: the toast is NOT fired when the window is focused OR when '
        'notificationsReady is false', () async {
      // Focused branch: even with growth + a non-active conversation, no
      // toast fires (the gate's `!focused` half).
      final hFocused = _Harness();
      addTearDown(hFocused.container.dispose);
      hFocused.setFocus(true);
      hFocused.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [_channelMsg('peer', 'peerfp')],
        ),
      ]);
      await _poll(hFocused.container);
      hFocused.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [
            _channelMsg('peer', 'peerfp'),
            _channelMsg('peer', 'peerfp')
          ],
        ),
      ]);
      await _poll(hFocused.container);
      expect(hFocused.notifications.shows, isEmpty);

      // Unfocused but the gate is closed: no toast either.
      final hNotReady = _Harness(notificationsReady: false);
      addTearDown(hNotReady.container.dispose);
      hNotReady.setFocus(false);
      hNotReady.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [_channelMsg('peer', 'peerfp')],
        ),
      ]);
      await _poll(hNotReady.container);
      hNotReady.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [
            _channelMsg('peer', 'peerfp'),
            _channelMsg('peer', 'peerfp')
          ],
        ),
      ]);
      await _poll(hNotReady.container);
      expect(hNotReady.notifications.shows, isEmpty);
      expect(
        hNotReady.container.read(unreadLifecycleProvider)['channel:general'],
        1,
      );
    });

    test('case 5: a channel key toast body renders #name', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.setFocus(false);
      h.gateway.seedChannels([
        _channel(
          name: 'watercooler',
          deviceFingerprint: 'ownfp',
          messages: [_channelMsg('peer', 'peerfp')],
        ),
      ]);
      await _poll(h.container);
      h.gateway.seedChannels([
        _channel(
          name: 'watercooler',
          deviceFingerprint: 'ownfp',
          messages: [
            _channelMsg('peer', 'peerfp'),
            _channelMsg('peer', 'peerfp')
          ],
        ),
      ]);
      await _poll(h.container);

      expect(h.notifications.shows.length, 1);
      expect(h.notifications.shows.single.title, 'Mosh');
      expect(h.notifications.shows.single.body, '#watercooler - new message');
    });

    test('case 6: a first-seen conversation never notifies (no baseline)',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.setFocus(false);
      // A group appears for the first time with several peer messages;
      // first-seen has no baseline so diffConversations reports nothing.
      h.gateway.seedGroups([
        _group(
          groupId: 'g1',
          deviceFingerprint: 'ownfp',
          messages: [_groupMsg('peer', 'peerfp'), _groupMsg('peer', 'peerfp')],
        ),
      ]);
      await _poll(h.container);

      expect(h.container.read(unreadLifecycleProvider), isEmpty);
      expect(h.notifications.shows, isEmpty);
    });

    test('clearUnread(key) removes the key from the exposed unread map',
        () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      // Grow a non-active channel so the unread map gains an entry.
      h.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [_channelMsg('peer', 'peerfp')],
        ),
      ]);
      await _poll(h.container);
      h.gateway.seedChannels([
        _channel(
          name: 'general',
          deviceFingerprint: 'ownfp',
          messages: [
            _channelMsg('peer', 'peerfp'),
            _channelMsg('peer', 'peerfp')
          ],
        ),
      ]);
      await _poll(h.container);
      expect(h.container.read(unreadLifecycleProvider)['channel:general'], 1);

      // clearUnread drops the key from the exposed unread map.
      h.container
          .read(unreadLifecycleProvider.notifier)
          .clearUnread('channel:general');
      expect(
          h.container.read(unreadLifecycleProvider)['channel:general'], isNull);
    });
  });
}
