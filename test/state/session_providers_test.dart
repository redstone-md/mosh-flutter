// S4.0: verifies the four slice-one Riverpod providers over the FakeGateway.
// Uses ProviderContainer (Riverpod v3) + flutter_test. Per ADR 0013 + S5 the
// gatewayProvider default is now RealBridgeGateway (real Rust), which cannot
// run under `flutter test` (no native cdylib). These provider tests exercise
// FakeGateway behaviour, so each container overrides gatewayProvider with a
// fresh FakeGateway instance; the test still proves the seam end-to-end.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

Gateway _fakeGateway() => FakeGateway();

void main() {
  test('sessionListProvider resolves to the FakeGateway empty initial list',
      () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(_fakeGateway()),
    ]);
    addTearDown(container.dispose);

    final snapshot =
        await container.read(sessionListProvider.future);
    expect(snapshot.sessions, isEmpty);
  });

  test('inviteFlowProvider.create() populates lastInvite and the session '
      'appears in sessionListProvider after refresh', () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(_fakeGateway()),
    ]);
    addTearDown(container.dispose);

    container.read(inviteFlowProvider.notifier).setDisplayName('alice');
    final invite = await container.read(inviteFlowProvider.notifier).create();
    expect(invite.sessionId, isNotEmpty);
    expect(container.read(inviteFlowProvider).lastInvite?.sessionId,
        invite.sessionId);

    // The FakeGateway mutated its in-memory map; refresh the server-state
    // cache so sessionListProvider sees the new session.
    await container.read(sessionListProvider.notifier).refresh();
    final snapshot = await container.read(sessionListProvider.future);
    expect(snapshot.sessions.map((s) => s.sessionId),
        contains(invite.sessionId));
  });
}
