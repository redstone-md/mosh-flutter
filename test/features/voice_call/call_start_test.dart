import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/voice_call_start_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../../support/message_builders.dart';
import '../../support/scriptable_bridge.dart';

void main() {
  test('a pre-start list result cannot release failed confirmation admission',
      () async {
    final bridge = ScriptableBridge()..hold(BridgeMethod.callStart);
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    final starter = container.read(voiceCallStartProvider.notifier);
    final first = starter.start('first');
    await Future<void>.delayed(Duration.zero);
    final preStartRead = Completer<SessionListSnapshot>();
    bridge.respondNext(BridgeMethod.listSessions, preStartRead.future);
    final background = container
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh(background: true);
    await Future<void>.delayed(Duration.zero);
    bridge.release(BridgeMethod.callStart);
    await Future<void>.delayed(Duration.zero);
    bridge.failNext(BridgeMethod.listSessions);
    preStartRead.complete(const SessionListSnapshot(sessions: []));
    await Future.wait([first, background]);
    expect(await starter.start('second'), isA<CallAlreadyInProgress>());
    expect(bridge.countOf(BridgeMethod.callStart), 1);
    await container
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh();
    expect(await starter.start('second'), isNull);
  });

  test('an existing call blocks a start in another DM', () async {
    final bridge = ScriptableBridge()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin',
            activeCall: TestCalls.active(callId: 'call-origin')),
      ]);
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    final starter = container.read(voiceCallStartProvider.notifier);
    // Admission must await the initial list too, before its first start.
    final result = await starter.start('other');
    expect(result, isA<CallAlreadyInProgress>());
    expect(bridge.countOf(BridgeMethod.callStart), 0);
  });

  test('a pending start blocks another DM', () async {
    final bridge = ScriptableBridge()..hold(BridgeMethod.callStart);
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    final starter = container.read(voiceCallStartProvider.notifier);
    final first = starter.start('first');
    await Future<void>.delayed(Duration.zero);
    expect(await starter.start('second'), isA<CallAlreadyInProgress>());
    expect(bridge.countOf(BridgeMethod.callStart), 1);
    bridge.release(BridgeMethod.callStart);
    expect(await first, isNull);
    expect(container.read(voiceCallStartProvider), isFalse);
  });

  test('a rejected start releases admission for a retry', () async {
    final bridge = ScriptableBridge()..failNext(BridgeMethod.callStart);
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    final starter = container.read(voiceCallStartProvider.notifier);
    expect(await starter.start('first'), isNotNull);
    expect(await starter.start('first'), isNull);
    expect(bridge.countOf(BridgeMethod.callStart), 2);
  });

  test('a failed confirmation retains admission until a successful poll',
      () async {
    final bridge = ScriptableBridge()..hold(BridgeMethod.callStart);
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    final starter = container.read(voiceCallStartProvider.notifier);
    final first = starter.start('first');
    await Future<void>.delayed(Duration.zero);
    bridge.failNext(BridgeMethod.listSessions);
    bridge.release(BridgeMethod.callStart);
    expect(await first, isNull);
    expect(await starter.start('second'), isA<CallAlreadyInProgress>());
    await container
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh();
    expect(await starter.start('second'), isNull);
    expect(bridge.countOf(BridgeMethod.callStart), 2);
  });
}
