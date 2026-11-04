// Unit tests for `unreadCounts` + `unreadCountsProvider`, the one unread
// family all three conversation kinds share. A `ProviderContainer`
// overrides `bridgeFacadeProvider` with a scripted bridge whose list reads
// return a controlled snapshot, then asserts the derived unread map. Which
// messages count as unread is the core's decision (its read-mark tests).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../support/scriptable_bridge.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/conversation/read_marks.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/unread_providers.dart';

SessionSnapshot _session({required String sessionId, int? unread}) =>
    SessionSnapshot(
      inviteAvailable: false,
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: '',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'AA',
      messages: const [],
      unread: unread == null ? null : UnreadState(count: unread),
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

ChannelSnapshot _channel({required String name, required int unread}) =>
    ChannelSnapshot(
      name: name,
      topic: '',
      meshId: 'm',
      displayName: 'me',
      deviceFingerprint: 'ownfp',
      messages: const [],
      unread: UnreadState(count: unread),
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

GroupSnapshot _group({required String groupId, required int unread}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'm',
      label: null,
      displayName: 'me',
      deviceFingerprint: 'ownfp',
      creatorFingerprint: 'ownfp',
      isAdmin: false,
      state: 'ready',
      memberCount: BigInt.two,
      messages: const [],
      unread: UnreadState(count: unread),
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
    test('a snapshot without the core report counts as nothing unread', () {
      final counts = unreadCounts(DmConversationList(SessionListSnapshot(
        sessions: [
          _session(sessionId: 'a', unread: 2),
          _session(sessionId: 'b'),
        ],
      )));

      expect(counts, {'dm:a': 2, 'dm:b': 0});
    });
  });

  group('unreadCountsProvider', () {
    test('recomputes when the DM list refreshes', () async {
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

      bridge.seedSessions([_session(sessionId: 'a', unread: 2)]);
      await container
          .read(conversationListProvider(ConversationKind.dm).notifier)
          .refresh();
      final counts = await container
          .read(unreadCountsProvider(ConversationKind.dm).future);
      expect(counts, {'dm:a': 2});
    });

    test('each kind carries its own counts under its own key', () async {
      final bridge = ScriptableBridge()
        ..seedSessions([_session(sessionId: 'a', unread: 1)])
        ..seedChannels([_channel(name: 'general', unread: 2)])
        ..seedGroups([_group(groupId: 'g', unread: 3)]);
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
          {'channel:general': 2});
      expect(
          await container
              .read(unreadCountsProvider(ConversationKind.group).future),
          {'group:g': 3});
    });
  });
}
