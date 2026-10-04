import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final host in <DmOfferHost<Object?>>[
    const ChannelTarget('channel'),
    const GroupTarget('group'),
  ]) {
    final method = host is GroupTarget
        ? BridgeMethod.sendGroupDmOffer
        : BridgeMethod.sendChannelDmOffer;

    test('${host.kind.name}: failed DM offer closes only its new invite',
        () async {
      final gateway = ScriptableGateway();
      final error = Exception('publication failed');
      final bridge = ScriptableBridge(conversations: gateway.conversations)
        ..failNext(method, error: error);
      final container = ProviderContainer(overrides: [
        gatewayProvider.overrideWithValue(gateway),
        bridgeFacadeProvider.overrideWithValue(bridge),
      ]);
      addTearDown(container.dispose);
      final controller =
          container.read(conversationControllerProvider(host).notifier);
      await expectLater(controller.onPeerMessage('peer'), throwsA(same(error)));
      expect(gateway.lastCall(GatewayMethod.leave)?.target,
          const DmTarget('fake-1'));
      expect(gateway.conversations.sessions, isEmpty);
      expect(container.read(conversationControllerProvider(host)).offerBusy,
          isFalse);
      final retry = await controller.onPeerMessage('peer');
      expect(retry.sessionId, 'fake-1');
    });

    test('${host.kind.name}: published DM remains usable and is not duplicated',
        () async {
      final gateway = ScriptableGateway();
      final bridge = ScriptableBridge(conversations: gateway.conversations);
      final container = ProviderContainer(overrides: [
        gatewayProvider.overrideWithValue(gateway),
        bridgeFacadeProvider.overrideWithValue(bridge),
      ]);
      addTearDown(container.dispose);
      final controller =
          container.read(conversationControllerProvider(host).notifier);
      final result = await controller.onPeerMessage('peer');
      expect(result.sessionId, 'fake-1');
      expect(gateway.conversations.sessions.keys, ['fake-1']);
      expect(gateway.countOf(GatewayMethod.leave), 0);
      await controller.onPeerMessage('peer');
      expect(bridge.countOf(BridgeMethod.createInvite), 1);
    });
  }

  test('DM cleanup failure preserves the publication error', () async {
    final gateway = ScriptableGateway()
      ..failNext(GatewayMethod.leave, error: Exception('cleanup failed'));
    final error = Exception('publication failed');
    final bridge = ScriptableBridge(conversations: gateway.conversations)
      ..failNext(BridgeMethod.sendGroupDmOffer, error: error);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(
      conversationControllerProvider(const GroupTarget('group')).notifier,
    );
    await expectLater(controller.onPeerMessage('peer'), throwsA(same(error)));
    expect(gateway.countOf(GatewayMethod.leave), 1);
  });
}
