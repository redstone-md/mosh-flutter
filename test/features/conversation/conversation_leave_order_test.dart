import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_text_sends.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

ProviderContainer _container(ScriptableGateway gateway) {
  final container = ProviderContainer(overrides: [
    gatewayProvider.overrideWithValue(gateway),
  ]);
  addTearDown(container.dispose);
  return container;
}

Completer<void> _heldSend(ScriptableGateway gateway) {
  final pending = Completer<void>();
  gateway.respondNext(GatewayMethod.send, pending.future);
  addTearDown(() {
    if (!pending.isCompleted) pending.complete();
  });
  return pending;
}

void main() {
  for (final testCase in conversationCases()) {
    final target = testCase.target;
    final provider = conversationTextSendsProvider(target);

    test('${testCase.label}: leave follows every accepted text submission',
        () async {
      final gateway = ScriptableGateway();
      final pending = _heldSend(gateway);
      final container = _container(gateway);
      final controller =
          container.read(conversationControllerProvider(target).notifier);
      final first = controller.sendBody('first');
      final second = controller.sendBody('second');
      await Future<void>.delayed(Duration.zero);
      final leaving = controller.leave();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.countOf(GatewayMethod.leave), 0);
      expect((await controller.retryFailedSend()).sent, isFalse);
      final refused = await controller.sendBody('during close');
      expect(refused.sent, isFalse);
      expect(refused.body, 'during close');

      pending.complete();
      expect((await Future.wait([first, second])).every((r) => r.sent), isTrue);
      expect(await leaving, isTrue);
      expect(gateway.calls.map((call) => call.method),
          [GatewayMethod.send, GatewayMethod.send, GatewayMethod.leave]);
      expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
          ['first', 'second']);
    });

    test(
        '${testCase.label}: failed leave preserves refused texts and reopens sends',
        () async {
      final gateway = ScriptableGateway()..failNext(GatewayMethod.leave);
      final pending = _heldSend(gateway);
      final container = _container(gateway);
      final controller =
          container.read(conversationControllerProvider(target).notifier);
      final first = controller.sendBody('first');
      final second = controller.sendBody('second');
      await Future<void>.delayed(Duration.zero);
      final leaving = controller.leave();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.countOf(GatewayMethod.leave), 0);

      pending.completeError(Exception('admission refused'));
      await Future.wait([first, second]);
      expect(await leaving, isFalse);
      expect(container.read(provider).firstFailure?.body, 'first');
      expect((await controller.sendBody('after failed close')).sent, isTrue);
      expect((await controller.retryFailedSend()).sent, isTrue);
      expect(container.read(provider).failures, isEmpty);
      expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
          ['first', 'second', 'after failed close', 'first']);
    });

    test('${testCase.label}: repeated leave does not race the first close',
        () async {
      final gateway = ScriptableGateway();
      final pending = _heldSend(gateway);
      final container = _container(gateway);
      final controller =
          container.read(conversationControllerProvider(target).notifier);
      final sending = controller.sendBody('first');
      await Future<void>.delayed(Duration.zero);
      final leaving = controller.leave();
      expect(await controller.leave(), isFalse);
      expect(gateway.countOf(GatewayMethod.leave), 0);
      pending.complete();
      await sending;
      expect(await leaving, isTrue);
      expect(gateway.countOf(GatewayMethod.leave), 1);
    });
  }

  test('disposal while draining prevents the deferred close', () async {
    final gateway = ScriptableGateway();
    final pending = _heldSend(gateway);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
    ]);
    final controller = container.read(
        conversationControllerProvider(conversationCases().first.target)
            .notifier);
    final sending = controller.sendBody('first');
    await Future<void>.delayed(Duration.zero);
    final leaving = controller.leave();
    container.dispose();
    pending.complete();
    await sending;
    expect(await leaving, isFalse);
    expect(gateway.countOf(GatewayMethod.leave), 0);
  });
}
