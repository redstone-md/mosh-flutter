// Unit tests for `unreadCounts` + `unreadCountsProvider`, the one unread
// family all three conversation kinds share. Mirrors the established
// provider-test pattern (test/state/session_providers_test.dart): a
// `ProviderContainer` overrides `bridgeFacadeProvider` with a scripted
// bridge whose list reads return a controlled snapshot, then asserts the
// derived unread map.
//
// The DM-name vs. fingerprint rationale behind [unreadCounts] is written
// once, in `unread_providers.dart`. The channel and group cases below pin
// the fingerprint half of that one branch: a same-named peer must still
// count, and a renamed self must not.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../support/scriptable_bridge.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/unread_providers.dart';

ChatMessage _dmMessage(String fromDevice, {String body = 'x'}) => ChatMessage(
      fromDevice: fromDevice,
      body: body,
    );

ChannelMessage _channelMessage(String fromDevice, String fromFingerprint,
        {String body = 'x'}) =>
    ChannelMessage(
        fromDevice: fromDevice, fromFingerprint: fromFingerprint, body: body);

GroupMessage _groupMessage(String fromDevice, String fromFingerprint,
        {String body = 'x'}) =>
    GroupMessage(
        fromDevice: fromDevice, fromFingerprint: fromFingerprint, body: body);

SessionSnapshot _session({
  required String sessionId,
  required String displayName,
  required List<ChatMessage> messages,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: '',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'AA',
      messages: messages,
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

ChannelSnapshot _channel({
  required String name,
  required String deviceFingerprint,
  required List<ChannelMessage> messages,
}) =>
    ChannelSnapshot(
      name: name,
      topic: '',
      meshId: 'm',
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

GroupSnapshot _group({
  required String groupId,
  required String deviceFingerprint,
  required List<GroupMessage> messages,
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'm',
      label: null,
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      creatorFingerprint: deviceFingerprint,
      isAdmin: false,
      state: 'ready',
      memberCount: BigInt.two,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      memberPeerIds: const [],
      typingMembers: const [],
    );

void main() {
  group('unreadCounts', () {
    test('DM: counts not-own messages per session keyed by dm:<sessionId>', () {
      final counts = unreadCounts(DmConversationList(SessionListSnapshot(
        sessions: [
          _session(
            sessionId: 'a',
            displayName: 'me',
            messages: [
              _dmMessage('me'),
              _dmMessage('peer'),
              _dmMessage('me'),
              _dmMessage('peer'),
            ],
          ),
          _session(
            sessionId: 'b',
            displayName: 'me',
            messages: [
              _dmMessage('me'),
              _dmMessage('me'),
              _dmMessage('me'),
            ],
          ),
          _session(
            sessionId: 'c',
            displayName: 'me',
            messages: [_dmMessage('peer')],
          ),
        ],
      )));

      expect(counts, {'dm:a': 2, 'dm:b': 0, 'dm:c': 1});
    });

    test('channel: compares fingerprints, not display names', () {
      final counts = unreadCounts(ChannelConversationList(ChannelListSnapshot(
        channels: [
          _channel(
            name: 'general',
            deviceFingerprint: 'ownfp',
            messages: [
              _channelMessage('me', 'ownfp'),
              _channelMessage('peer', 'peerfp'),
              // Same display name as us, different fingerprint: still
              // someone else's message.
              _channelMessage('me', 'otherfp'),
            ],
          ),
          _channel(
            name: 'random',
            deviceFingerprint: 'ownfp',
            messages: [
              // We renamed ourselves: the old name must not count.
              _channelMessage('oldname', 'ownfp'),
            ],
          ),
        ],
      )));

      expect(counts, {'channel:general': 2, 'channel:random': 0});
    });

    test('group: compares fingerprints, keyed by group:<groupId>', () {
      final counts = unreadCounts(GroupConversationList(GroupListSnapshot(
        groups: [
          _group(
            groupId: 'g',
            deviceFingerprint: 'ownfp',
            messages: [
              _groupMessage('me', 'ownfp'),
              _groupMessage('peer', 'peerfp'),
              _groupMessage('me', 'otherfp'),
            ],
          ),
        ],
      )));

      expect(counts, {'group:g': 2});
    });

    test('an empty list yields an empty map', () {
      expect(
          unreadCounts(
              const DmConversationList(SessionListSnapshot(sessions: []))),
          isEmpty);
    });
  });

  group('unreadCountsProvider', () {
    test('resolves to the derived map over the seeded snapshot', () async {
      final bridge = ScriptableBridge()
        ..seedSessions([
          _session(
            sessionId: 'a',
            displayName: 'me',
            messages: [
              _dmMessage('me'),
              _dmMessage('peer'),
              _dmMessage('me'),
              _dmMessage('peer'),
            ],
          ),
          _session(
            sessionId: 'b',
            displayName: 'me',
            messages: [
              _dmMessage('me'),
              _dmMessage('me'),
              _dmMessage('me'),
            ],
          ),
          _session(
            sessionId: 'c',
            displayName: 'me',
            messages: [_dmMessage('peer')],
          ),
        ]);

      final container = ProviderContainer(overrides: [
        bridgeFacadeProvider.overrideWithValue(bridge),
      ]);
      addTearDown(container.dispose);

      // The DM list entry must resolve first so the chained count provider
      // has data to derive from.
      await container
          .read(conversationListProvider(ConversationKind.dm).future);
      final counts = await container
          .read(unreadCountsProvider(ConversationKind.dm).future);

      expect(counts['dm:a'], 2);
      expect(counts['dm:b'], 0);
      expect(counts['dm:c'], 1);
    });

    test('recomputes when the DM list refreshes', () async {
      // Start empty; refresh swaps the snapshot to one with an unread
      // session and the derived map updates on the next read.
      final bridge = ScriptableBridge();
      final container = ProviderContainer(overrides: [
        bridgeFacadeProvider.overrideWithValue(bridge),
      ]);
      addTearDown(container.dispose);

      await container
          .read(conversationListProvider(ConversationKind.dm).future);
      expect(
          await container
              .read(unreadCountsProvider(ConversationKind.dm).future),
          isEmpty);

      bridge.seedSessions([
        _session(
          sessionId: 'a',
          displayName: 'me',
          messages: [_dmMessage('peer'), _dmMessage('peer')],
        ),
      ]);
      await container
          .read(conversationListProvider(ConversationKind.dm).notifier)
          .refresh();
      final counts = await container
          .read(unreadCountsProvider(ConversationKind.dm).future);
      expect(counts, {'dm:a': 2});
    });

    test('each kind carries its own counts', () async {
      final bridge = ScriptableBridge()
        ..seedSessions([
          _session(
            sessionId: 'a',
            displayName: 'me',
            messages: [_dmMessage('peer')],
          ),
        ])
        ..seedChannels([
          _channel(
            name: 'general',
            deviceFingerprint: 'ownfp',
            messages: [_channelMessage('peer', 'peerfp')],
          ),
        ])
        ..seedGroups([
          _group(
            groupId: 'g',
            deviceFingerprint: 'ownfp',
            messages: [_groupMessage('peer', 'peerfp')],
          ),
        ]);
      final container = ProviderContainer(overrides: [
        bridgeFacadeProvider.overrideWithValue(bridge),
      ]);
      addTearDown(container.dispose);

      expect(
          await container
              .read(unreadCountsProvider(ConversationKind.dm).future),
          {'dm:a': 1});
      expect(
          await container
              .read(unreadCountsProvider(ConversationKind.channel).future),
          {'channel:general': 1});
      expect(
          await container
              .read(unreadCountsProvider(ConversationKind.group).future),
          {'group:g': 1});
    });
  });
}
