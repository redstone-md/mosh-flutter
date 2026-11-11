import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

/// A call shown by the host's own controls, as on a platform without a native
/// call engine.
class _Fixture {
  final gateway = ScriptableGateway();
  late final bridge = ScriptableBridge(conversations: gateway.conversations);
  var opened = 0;
  late final container = ProviderContainer(overrides: [
    gatewayProvider.overrideWithValue(gateway),
    bridgeFacadeProvider.overrideWithValue(bridge),
  ]);

  void seed({bool active = false, String id = 'call'}) {
    gateway.seedSessions([
      TestSnapshots.dm(
        sessionId: 'origin',
        pendingCall: active
            ? null
            : PendingCall(
                answerPending: false, callId: id, fromDevice: 'Alice'),
        activeCall: active ? TestCalls.active(callId: id) : null,
      )
    ]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
  }

  void merge(String superseded) {
    gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin',
          pendingCall: PendingCall(
              callId: 'canonical',
              supersededCallId: superseded,
              fromDevice: 'Alice',
              answerPending: true))
    ]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
  }

  Future<void> mount(WidgetTester tester) async {
    seed();
    await pumpScreen(
        tester,
        VoiceCallHost(
            onOpenConversation: (_) => opened++, child: const Scaffold()),
        container: container,
        settle: false);
    await frames(tester);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

CallView _shown(WidgetTester tester) =>
    tester.widget<CallView>(find.byType(CallView));

/// Declines, cancels or hangs up, whichever the shown call offers.
Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.phone_disabled));
  await frames(tester);
}

void main() {
  testWidgets('cancel survives an authenticated merge during its control wait',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    final accepted = Completer<void>();
    f.bridge.respondNext(BridgeMethod.callAccept, accepted.future);
    await f.mount(tester);
    await tester.tap(find.byTooltip('Accept call'));
    await frames(tester);
    await _close(tester);
    f.merge('call');
    await frames(tester);
    accepted.complete();
    await frames(tester);
    expect(f.bridge.lastCall(BridgeMethod.callEnd)?.arg<String>('callId'),
        'canonical');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'a merged call honors the cancel from its previously displayed ID',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    await f.mount(tester);
    f.gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin',
          outgoingCall: const OutgoingCall(callId: 'original'))
    ]);
    f.container.invalidate(conversationListProvider(ConversationKind.dm));
    await frames(tester);
    final previous = _shown(tester);
    f.merge('original');
    await frames(tester);
    previous.onAction(CallViewAction.end);
    await frames(tester);
    expect(f.bridge.countOf(BridgeMethod.callEnd), 1);
    expect(f.bridge.lastCall(BridgeMethod.callEnd)?.arg<String>('callId'),
        'canonical');
    expect(f.bridge.countOf(BridgeMethod.callDecline), 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('the peer name opens the origin while accept is pending',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    f.bridge.hold(BridgeMethod.callAccept);
    await f.mount(tester);
    await tester.tap(find.byTooltip('Accept call'));
    await frames(tester);
    expect(_shown(tester).call.busy, isTrue);
    await tester.tap(find.descendant(
        of: find.byType(CallModalCard),
        matching: find.text(_shown(tester).call.peer)));
    await frames(tester);
    expect(f.opened, 1);
    expect(f.bridge.countOf(BridgeMethod.callEnd), 0);
    expect(f.bridge.countOf(BridgeMethod.callDecline), 0);
    f.bridge.release(BridgeMethod.callAccept);
    await frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    f.container.dispose();
    await tester.pump();
  });

  testWidgets('closing a replacement never waits for the old accept',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    final accepted = Completer<void>();
    f.bridge.respondNext(BridgeMethod.callAccept, accepted.future);
    await f.mount(tester);
    await tester.tap(find.byTooltip('Accept call'));
    await frames(tester);
    f.seed(id: 'replacement');
    await frames(tester);
    await _close(tester);
    expect(f.bridge.lastCall(BridgeMethod.callDecline)?.arg<String>('callId'),
        'replacement');
    accepted.complete();
    await frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    f.container.dispose();
    await tester.pump();
  });

  testWidgets('late incoming decline cannot end the same active call',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    await f.mount(tester);
    final ringing = _shown(tester);
    f.seed(active: true);
    await frames(tester);
    ringing.onAction(CallViewAction.decline);
    await frames(tester);
    expect(f.bridge.countOf(BridgeMethod.callDecline), 0);
    expect(f.bridge.countOf(BridgeMethod.callEnd), 0);
    expect(_shown(tester).call.phase, CallViewPhase.active);
    await tester.pumpWidget(const SizedBox.shrink());
    f.container.dispose();
    await tester.pump();
  });

  for (final outcome in ['accepted', 'failed', 'replaced']) {
    testWidgets('close waits for accept: $outcome', (tester) async {
      final f = _Fixture();
      addTearDown(f.container.dispose);
      final accepted = Completer<void>();
      f.bridge.respondNext(BridgeMethod.callAccept, accepted.future);
      await f.mount(tester);
      await tester.tap(find.byTooltip('Accept call'));
      await frames(tester);
      await _close(tester);
      expect(f.bridge.countOf(BridgeMethod.callEnd), 0);
      if (outcome == 'replaced') {
        f.seed(id: 'replacement');
        await frames(tester);
      }
      if (outcome == 'failed') {
        accepted.completeError(StateError('accept failed'));
      } else {
        accepted.complete();
      }
      await frames(tester);
      expect(f.bridge.countOf(BridgeMethod.callEnd),
          outcome == 'accepted' ? 1 : 0);
      expect(f.bridge.countOf(BridgeMethod.callDecline),
          outcome == 'failed' ? 1 : 0);
      if (outcome == 'replaced') {
        expect(_shown(tester).call.callId, 'replacement');
      } else {
        expect(find.byType(CallView), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      f.container.dispose();
      await tester.pump();
    });
  }
}
