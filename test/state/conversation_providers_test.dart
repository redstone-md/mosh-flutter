// The state layer's one conversation kind branch, pinned: one list family,
// one invalidate switch, one refresh switch.
//
// The gateway is a ScriptableGateway, so "did the branch pick the right
// family" is answered by counting calls: `listSessions` / `listChannels` /
// `listGroups` for a list entry, `poll` for a snapshot. Each entry is
// subscribed to before it is measured -- Riverpod 3 auto-disposes by
// default, so without a listener a second read would re-run the gateway
// call on its own and the count would prove nothing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/gateway_snapshots.dart'
    show cannedChannelSnapshot, cannedGroupSnapshot, fakeSession;
import '../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;

/// One kind: the target that names it and the Gateway method that lists it.
class _KindCase {
  const _KindCase(this.target, this.listMethod);

  final AnyConversationTarget target;
  final GatewayMethod listMethod;

  ConversationKind get kind => target.kind;
}

/// The three kinds, each with the id [_seedOneOfEachKind] gives it.
const _kindCases = <_KindCase>[
  _KindCase(DmTarget('a'), GatewayMethod.listSessions),
  _KindCase(ChannelTarget('general'), GatewayMethod.listChannels),
  _KindCase(GroupTarget('g'), GatewayMethod.listGroups),
];

/// Seeds one conversation of each kind, so every snapshot family resolves.
void _seedOneOfEachKind(ScriptableGateway gateway) => gateway
  ..seedSessions([
    fakeSession(
      sessionId: 'a',
      displayName: 'me',
      role: 'inviter',
      inviteUri: '',
      fingerprint: 'fp',
    ),
  ])
  ..seedChannels([cannedChannelSnapshot(name: 'general')])
  ..seedGroups([cannedGroupSnapshot(groupId: 'g')]);

/// A container whose gateway is this test's [gateway].
ProviderContainer _container(ScriptableGateway gateway) {
  final container = ProviderContainer(overrides: [
    gatewayProvider.overrideWithValue(gateway),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('conversationListProvider', () {
    test('the DM entry reads sessions and no other kind', () async {
      final gateway = ScriptableGateway();
      final container = _container(gateway);

      final list = await container
          .read(conversationListProvider(ConversationKind.dm).future);

      expect(sessionsOf(list), isEmpty);
      // The branch, pinned: a DM entry that read channels or groups instead
      // would still hand back an empty DM slice.
      expect(gateway.countOf(GatewayMethod.listSessions), 1);
      expect(gateway.countOf(GatewayMethod.listChannels), 0);
      expect(gateway.countOf(GatewayMethod.listGroups), 0);
    });

    test(
        'a session created through inviteFlowProvider appears in the DM list '
        'after a refresh', () async {
      final container = _container(ScriptableGateway());

      container.read(inviteFlowProvider.notifier).setDisplayName('alice');
      final invite = await container.read(inviteFlowProvider.notifier).create();
      expect(invite.sessionId, isNotEmpty);

      // The gateway mutated its in-memory map; refresh the DM entry so it
      // re-reads the new session.
      await container
          .read(conversationListProvider(ConversationKind.dm).notifier)
          .refresh();
      final list = await container
          .read(conversationListProvider(ConversationKind.dm).future);

      expect(
          sessionsOf(list).map((s) => s.sessionId), contains(invite.sessionId));
    });
  });

  group('refreshConversationLists', () {
    test('re-reads the list of every kind', () async {
      final gateway = ScriptableGateway();
      _seedOneOfEachKind(gateway);
      final container = _container(gateway);
      for (final c in _kindCases) {
        await container.read(conversationListProvider(c.kind).future);
      }
      final before = {
        for (final c in _kindCases) c.kind: gateway.countOf(c.listMethod),
      };

      await refreshConversationLists(container.read);

      for (final c in _kindCases) {
        expect(gateway.countOf(c.listMethod), before[c.kind]! + 1,
            reason: 'the ${c.kind.name} list re-read once');
      }
    });
  });

  group('invalidateConversation', () {
    test('re-reads the snapshot family the kind names', () async {
      final gateway = ScriptableGateway();
      _seedOneOfEachKind(gateway);
      final container = _container(gateway);

      for (final c in _kindCases) {
        // Subscribing keeps the entry alive, so only the invalidate below
        // can make the next read re-run the gateway call.
        final subscription =
            container.listen(conversationSnapshotProvider(c.target), (_, __) {
          // The value is read below; this only holds the entry open.
        });
        addTearDown(subscription.close);

        await container.read(conversationSnapshotProvider(c.target).future);
        final before = gateway.countOf(GatewayMethod.poll);
        await container.read(conversationSnapshotProvider(c.target).future);
        expect(gateway.countOf(GatewayMethod.poll), before,
            reason: '${c.target} is cached until something invalidates it');

        invalidateConversation(container.invalidate, c.target.ref);

        await container.read(conversationSnapshotProvider(c.target).future);
        expect(gateway.countOf(GatewayMethod.poll), before + 1,
            reason: '${c.target} re-read its snapshot');
      }
    });
  });

  group('refreshConversation', () {
    test('re-reads the snapshot, and the rail list of a DM only', () async {
      final gateway = ScriptableGateway();
      _seedOneOfEachKind(gateway);
      final container = _container(gateway);
      // Hold every entry open so only the refresh below can re-read one.
      final subscriptions = [
        for (final kind in ConversationKind.values)
          container.listen(conversationListProvider(kind), (_, __) {}),
        for (final c in _kindCases)
          container.listen(conversationSnapshotProvider(c.target), (_, __) {}),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      });
      for (final kind in ConversationKind.values) {
        await container.read(conversationListProvider(kind).future);
      }
      for (final c in _kindCases) {
        await container.read(conversationSnapshotProvider(c.target).future);
      }

      for (final c in _kindCases) {
        final beforePolls = gateway.countOf(GatewayMethod.poll);
        final beforeLists = {
          for (final other in _kindCases)
            other.kind: gateway.countOf(other.listMethod),
        };

        refreshConversation(container.invalidate, c.target.ref);

        // The invalidate half: the snapshot always re-reads. Without it the
        // rest of this test would still hold, so it is asserted first.
        await container.read(conversationSnapshotProvider(c.target).future);
        expect(gateway.countOf(GatewayMethod.poll), beforePolls + 1,
            reason: '${c.target} re-read its snapshot');

        // The rail-list half: only a DM's row carries its last message.
        for (final other in _kindCases) {
          // Reading a list re-runs it only when the refresh invalidated it.
          await container.read(conversationListProvider(other.kind).future);
          final reRead = c.kind == ConversationKind.dm &&
              other.kind == ConversationKind.dm;
          expect(gateway.countOf(other.listMethod),
              beforeLists[other.kind]! + (reRead ? 1 : 0),
              reason: 'the ${other.kind.name} list after a '
                  '${c.kind.name} refresh');
        }
      }
    });
  });
}
