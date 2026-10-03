import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../support/gateway_snapshots.dart';
import '../support/scriptable_bridge.dart';

SessionListSnapshot _list(String id) => SessionListSnapshot(sessions: [
      fakeSession(
          sessionId: id,
          displayName: id,
          role: 'inviter',
          inviteUri: '',
          fingerprint: 'fp'),
    ]);

void main() {
  test(
      'polling waits for the initial read while a mutation requests fresh data',
      () async {
    final initial = Completer<SessionListSnapshot>();
    final bridge = ScriptableBridge()
      ..seedSessions(_list('after-mutation').sessions)
      ..respondNext(BridgeMethod.listSessions, initial.future);
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
    ]);
    addTearDown(container.dispose);
    final provider = conversationListProvider(ConversationKind.dm);
    container.listen(provider, (_, __) {});
    final notifier = container.read(provider.notifier);
    await notifier.refresh(background: true);
    expect(bridge.countOf(BridgeMethod.listSessions), 1);
    final requested = notifier.refresh();
    expect(bridge.countOf(BridgeMethod.listSessions), 1);
    initial.complete(_list('before-mutation'));
    await requested;
    expect(sessionsOf(container.read(provider).requireValue).single.sessionId,
        'after-mutation');
  });

  test('overlapping requests serialize and read again after a mutation',
      () async {
    final bridge = ScriptableBridge()..seedSessions(_list('initial').sessions);
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
    ]);
    addTearDown(container.dispose);
    final provider = conversationListProvider(ConversationKind.dm);
    container.listen(provider, (_, __) {});
    await container.read(provider.future);
    final older = Completer<SessionListSnapshot>();
    final newer = Completer<SessionListSnapshot>();
    bridge.respondNext(BridgeMethod.listSessions, older.future);
    bridge.respondNext(BridgeMethod.listSessions, newer.future);
    final notifier = container.read(provider.notifier);
    final first = notifier.refresh();
    final second = notifier.refresh();
    final third = notifier.refresh();

    expect(bridge.countOf(BridgeMethod.listSessions), 2,
        reason: 'overlapping callers must share one outstanding native read');
    older.complete(_list('older'));
    await Future<void>.delayed(Duration.zero);
    expect(bridge.countOf(BridgeMethod.listSessions), 3,
        reason: 'requests during the read require one subsequent fresh read');
    newer.complete(_list('newer'));
    await Future.wait([first, second, third]);
    expect(
        sessionsOf(container.read(provider).requireValue)
            .map((session) => session.sessionId),
        ['newer']);
  });

  test('background ticks share a pending read without scheduling more work',
      () async {
    final bridge = ScriptableBridge()..seedSessions(_list('initial').sessions);
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
    ]);
    addTearDown(container.dispose);
    final provider = conversationListProvider(ConversationKind.dm);
    container.listen(provider, (_, __) {});
    await container.read(provider.future);
    final held = Completer<SessionListSnapshot>();
    bridge.respondNext(BridgeMethod.listSessions, held.future);
    final notifier = container.read(provider.notifier);
    final first = notifier.refresh(background: true);
    final second = notifier.refresh(background: true);
    held.complete(_list('current'));
    await Future.wait([first, second]);
    expect(bridge.countOf(BridgeMethod.listSessions), 2);
    expect(sessionsOf(container.read(provider).requireValue).single.sessionId,
        'current');
  });

  test('a bridge replacement rejects old answers and retains its own guard',
      () async {
    final oldBridge = ScriptableBridge();
    final newBridge = ScriptableBridge()
      ..seedSessions(_list('replacement').sessions);
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(oldBridge),
    ]);
    addTearDown(container.dispose);
    final provider = conversationListProvider(ConversationKind.dm);
    container.listen(provider, (_, __) {});
    await container.read(provider.future);
    final oldRead = Completer<SessionListSnapshot>();
    oldBridge.respondNext(BridgeMethod.listSessions, oldRead.future);
    final oldRefresh = container.read(provider.notifier).refresh();
    container
        .updateOverrides([bridgeFacadeProvider.overrideWithValue(newBridge)]);
    await container.read(provider.future);
    final newRead = Completer<SessionListSnapshot>();
    newBridge.respondNext(BridgeMethod.listSessions, newRead.future);
    final newRefresh = container.read(provider.notifier).refresh();
    oldRead.complete(_list('obsolete'));
    await oldRefresh;
    expect(sessionsOf(container.read(provider).requireValue).single.sessionId,
        'replacement');
    final background =
        container.read(provider.notifier).refresh(background: true);
    expect(newBridge.countOf(BridgeMethod.listSessions), 2);
    newRead.complete(_list('current'));
    await Future.wait([newRefresh, background]);
    expect(sessionsOf(container.read(provider).requireValue).single.sessionId,
        'current');
  });

  test('a failed refresh can be retried without losing the saved rows',
      () async {
    final bridge = ScriptableBridge()..seedSessions(_list('initial').sessions);
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
    ]);
    addTearDown(container.dispose);
    final provider = conversationListProvider(ConversationKind.dm);
    container.listen(provider, (_, __) {});
    await container.read(provider.future);
    bridge.failNext(BridgeMethod.listSessions);
    await container.read(provider.notifier).refresh();
    expect(container.read(provider).hasError, isTrue);
    await container.read(provider.notifier).refresh();
    expect(sessionsOf(container.read(provider).requireValue).single.sessionId,
        'initial');
  });
}
