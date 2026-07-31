// S4.0: verifies the four slice-one Riverpod providers over the FakeGateway.
// Uses ProviderContainer (Riverpod v3) + flutter_test. The FakeGateway is
// wired by gatewayProvider, so no overrides are needed; the test proves the
// seam works end-to-end.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/state/session_providers.dart';

void main() {
  test('sessionListProvider resolves to the FakeGateway empty initial list',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final snapshot =
        await container.read(sessionListProvider.future);
    expect(snapshot.sessions, isEmpty);
  });

  test('inviteFlowProvider.create() populates lastInvite and the session '
      'appears in sessionListProvider after refresh', () async {
    final container = ProviderContainer();
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
