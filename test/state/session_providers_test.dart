// S4.0: verifies the slice-one Riverpod providers that live in
// `session_providers.dart` over the test gateway. The DM LIST is not one of
// them: `conversationListProvider` serves all three kinds from
// `conversation_providers.dart`, and its tests are in
// conversation_providers_test.dart.
// Uses ProviderContainer (Riverpod v3) + flutter_test. Per ADR 0013 + S5 the
// gatewayProvider default is now RealBridgeGateway (real Rust), which cannot
// run under `flutter test` (no native cdylib). These provider tests exercise
// gateway state, so each container overrides gatewayProvider with a
// fresh gateway instance; the test still proves the seam end-to-end.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../support/scriptable_gateway.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  test('inviteFlowProvider.create() populates lastInvite', () async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
    ]);
    addTearDown(container.dispose);

    container.read(inviteFlowProvider.notifier).setDisplayName('alice');
    final invite = await container.read(inviteFlowProvider.notifier).create();

    expect(invite.sessionId, isNotEmpty);
    expect(container.read(inviteFlowProvider).lastInvite?.sessionId,
        invite.sessionId);
  });
}
