// Regression test for the lost AUTO_POLL_MS loop.
//
// The Flutter port dropped React's `usePrivateDmSnapshots` 1 s interval
// (use-private-dm-snapshots.ts L142). Because every Rust read entry point
// starts with `drain_inbound()`, "nothing polls" meant "nothing receives":
// a fresh session stayed `connecting` until BOTH peers sent, and peer
// messages only appeared after a local send. These tests pin that the
// loop re-queries the gateway with NO mutation in between.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/auto_poll_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// The one Gateway call that lists each conversation kind.
const _listMethods = <GatewayMethod>[
  GatewayMethod.listSessions,
  GatewayMethod.listChannels,
  GatewayMethod.listGroups,
];

void main() {
  test('the auto-poll loop re-queries the gateway with no mutation', () async {
    final gateway = ScriptableGateway();
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      autoPollIntervalProvider
          .overrideWithValue(const Duration(milliseconds: 10)),
    ]);
    addTearDown(container.dispose);

    // Resolve the DM list once so the initial build is not what we measure.
    await container.read(conversationListProvider(ConversationKind.dm).future);
    final baseline = <GatewayMethod, int>{
      for (final method in _listMethods) method: gateway.countOf(method),
    };

    container.read(autoPollProvider);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // The loop refreshes every kind, not just the one that happens to be
    // open: it goes through `refreshConversationLists`.
    for (final entry in baseline.entries) {
      expect(gateway.countOf(entry.key), greaterThan(entry.value),
          reason: '${entry.key.name} was re-read by the poll');
    }
  });

  test('no interval bound -> no polling (the flutter test default)', () async {
    final gateway = ScriptableGateway();
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);

    await container.read(conversationListProvider(ConversationKind.dm).future);
    final baseline = gateway.countOf(GatewayMethod.listSessions);

    container.read(autoPollProvider);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(gateway.countOf(GatewayMethod.listSessions), baseline);
  });
}
