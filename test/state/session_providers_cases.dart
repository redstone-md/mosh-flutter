// S4.0: verifies the slice-one Riverpod providers that live in
// `session_providers.dart` over the test bridge. The invite mint is a 1:1
// bridge mirror, so it reads `bridgeFacadeProvider` (ADR 0025); the DM poll
// seam has its own tests. Uses ProviderContainer (Riverpod v3) +
// flutter_test; the provider default is the real bridge (real Rust), which
// cannot run under `flutter test` (no native cdylib), so the container
// overrides it with a fresh scripted bridge.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../support/scriptable_bridge.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  test('inviteFlowProvider.create() populates lastInvite', () async {
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(ScriptableBridge()),
    ]);
    addTearDown(container.dispose);

    container.read(inviteFlowProvider.notifier).setDisplayName('alice');
    final invite = await container.read(inviteFlowProvider.notifier).create();

    expect(invite.sessionId, isNotEmpty);
    expect(container.read(inviteFlowProvider).lastInvite?.sessionId,
        invite.sessionId);
  });
}
