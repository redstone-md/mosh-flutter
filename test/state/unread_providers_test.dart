// Unit tests for `unreadDmCountsProvider` + `unreadDmCounts`. Mirrors the
// established provider-test pattern (test/state/session_providers_test.dart):
// a `ProviderContainer` overrides `gatewayProvider` with a fake whose
// `listSessions` returns a controlled `SessionListSnapshot`, then asserts the
// derived unread map. `countMessagesFromOthers` for DMs compares by display
// name (no fingerprint), so a message counts as "unread" iff its
// `fromDevice` differs from the session's `displayName`.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/unread_providers.dart';

ChatMessage _msg(String fromDevice, {String body = 'x'}) => ChatMessage(
      fromDevice: fromDevice,
      body: body,
    );

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
      state: 'ready',
      path: 'direct',
      relayReady: null,
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

/// FakeGateway whose `listSessions` returns a fixed snapshot so the
/// provider has a deterministic input. Other methods inherit the base
/// FakeGateway behaviour (unused here).
class _SeededGateway extends FakeGateway {
  _SeededGateway(this._snapshot);
  SessionListSnapshot _snapshot;

  @override
  Future<SessionListSnapshot> listSessions() => Future.value(_snapshot);
}

void main() {
  group('unreadDmCounts', () {
    test('counts not-own messages per session keyed by dm:<sessionId>', () {
      final snapshot = SessionListSnapshot(sessions: [
        _session(
          sessionId: 'a',
          displayName: 'me',
          messages: [
            _msg('me'),
            _msg('peer'),
            _msg('me'),
            _msg('peer'),
          ],
        ),
        _session(
          sessionId: 'b',
          displayName: 'me',
          messages: [_msg('me'), _msg('me'), _msg('me')],
        ),
        _session(
          sessionId: 'c',
          displayName: 'me',
          messages: [_msg('peer')],
        ),
      ]);

      final counts = unreadDmCounts(snapshot);

      expect(counts, {'dm:a': 2, 'dm:b': 0, 'dm:c': 1});
    });

    test('an empty session list yields an empty map', () {
      expect(unreadDmCounts(const SessionListSnapshot(sessions: [])), isEmpty);
    });
  });

  group('unreadDmCountsProvider', () {
    test('resolves to the derived map over the FakeGateway snapshot',
        () async {
      final gateway = _SeededGateway(SessionListSnapshot(sessions: [
        _session(
          sessionId: 'a',
          displayName: 'me',
          messages: [
            _msg('me'),
            _msg('peer'),
            _msg('me'),
            _msg('peer'),
          ],
        ),
        _session(
          sessionId: 'b',
          displayName: 'me',
          messages: [_msg('me'), _msg('me'), _msg('me')],
        ),
        _session(
          sessionId: 'c',
          displayName: 'me',
          messages: [_msg('peer')],
        ),
      ]));

      final container = ProviderContainer(overrides: [
        gatewayProvider.overrideWithValue(gateway),
      ]);
      addTearDown(container.dispose);

      // sessionListProvider must resolve first so the chained
      // unreadDmCountsProvider has data to derive from.
      await container.read(sessionListProvider.future);
      final counts = await container.read(unreadDmCountsProvider.future);

      expect(counts['dm:a'], 2);
      expect(counts['dm:b'], 0);
      expect(counts['dm:c'], 1);
    });

    test('recomputes when sessionListProvider refreshes', () async {
      // Start empty; refresh swaps the snapshot to one with an unread
      // session and the derived map updates on the next read.
      final gateway = _SeededGateway(const SessionListSnapshot(sessions: []));
      final container = ProviderContainer(overrides: [
        gatewayProvider.overrideWithValue(gateway),
      ]);
      addTearDown(container.dispose);

      await container.read(sessionListProvider.future);
      expect(await container.read(unreadDmCountsProvider.future), isEmpty);

      gateway._snapshot = SessionListSnapshot(sessions: [
        _session(
          sessionId: 'a',
          displayName: 'me',
          messages: [_msg('peer'), _msg('peer')],
        ),
      ]);
      await container.read(sessionListProvider.notifier).refresh();
      final counts = await container.read(unreadDmCountsProvider.future);
      expect(counts, {'dm:a': 2});
    });
  });
}
