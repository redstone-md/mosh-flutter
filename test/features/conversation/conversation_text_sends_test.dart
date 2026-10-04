import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_text_sends.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/scriptable_gateway.dart';

void main() {
  const target = DmTarget('test');
  final provider = conversationTextSendsProvider(target);

  ProviderContainer containerFor(ScriptableGateway gateway) {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('empty sends and retries do not call the gateway', () async {
    final gateway = ScriptableGateway();
    final container = containerFor(gateway);
    final sends = container.read(provider.notifier);
    expect((await sends.send('')).sent, isFalse);
    expect((await sends.retry()).sent, isFalse);
    expect(gateway.countOf(GatewayMethod.send), 0);
  });

  test('each refused submission survives later success and retries separately',
      () async {
    final gateway = ScriptableGateway()..failNext(GatewayMethod.send, times: 2);
    final container = containerFor(gateway);
    final sends = container.read(provider.notifier);
    await Future.wait([
      sends.send('first'),
      sends.send('second'),
      sends.send('third'),
    ]);
    expect(container.read(provider).failures.map((f) => f.body),
        ['first', 'second']);
    expect(container.read(provider).pending, 0);
    expect((await sends.retry()).sent, isTrue);
    expect(container.read(provider).firstFailure!.body, 'second');
    expect((await sends.retry()).sent, isTrue);
    expect(container.read(provider).failures, isEmpty);
    expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
        ['first', 'second', 'third', 'first', 'second']);
  });

  test('disposal stops queued admission and tolerates an in-flight refusal',
      () async {
    final first = Completer<void>();
    final gateway = ScriptableGateway()
      ..respondNext(GatewayMethod.send, first.future);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
    ]);
    final sends = container.read(provider.notifier);
    final results = Future.wait([sends.send('first'), sends.send('second')]);
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    first.completeError(Exception('disposed refusal'));
    expect((await results).every((r) => !r.sent), isTrue);
    expect(gateway.argValues<String>(GatewayMethod.send, 'body'), ['first']);
  });

  test(
      'invalidating a queue cancels its pending work without affecting a new one',
      () async {
    final first = Completer<void>();
    final gateway = ScriptableGateway()
      ..respondNext(GatewayMethod.send, first.future);
    final container = containerFor(gateway);
    final sends = container.read(provider.notifier);
    final old =
        Future.wait([sends.send('old first'), sends.send('old second')]);
    await Future<void>.delayed(Duration.zero);
    container.invalidate(provider);
    final fresh = container.read(provider.notifier);
    await fresh.send('new');
    first.complete();
    await old;
    expect(container.read(provider).pending, 0);
    expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
        ['old first', 'new']);
  });
}
