import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/voice_call_fakes.dart';

class _Fixture {
  final gateway = ScriptableGateway();
  late final bridge = ScriptableBridge(conversations: gateway.conversations);
  final window = RecordingCallWindow();
  late Future<void> Function(CallViewCommand) command;
  late final container = ProviderContainer(overrides: [
    gatewayProvider.overrideWithValue(gateway),
    bridgeFacadeProvider.overrideWithValue(bridge),
    callWindowFactoryProvider.overrideWithValue((handler) async {
      command = handler;
      return window;
    }),
  ]);

  void seed({bool active = false, String id = 'call'}) {
    gateway.seedSessions([
      TestSnapshots.dm(
        sessionId: 'origin',
        pendingCall:
            active ? null : PendingCall(callId: id, fromDevice: 'Alice'),
        activeCall: active ? TestCalls.active(callId: id) : null,
      )
    ]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
  }

  Future<void> mount(WidgetTester tester) async {
    seed();
    await pumpScreen(tester, const VoiceCallHost(child: Scaffold()),
        container: container, settle: false);
    await frames(tester);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets('closing a replacement never waits for the old accept',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    final accepted = Completer<void>();
    f.bridge.respondNext(BridgeMethod.callAccept, accepted.future);
    await f.mount(tester);
    final accepting =
        f.command(f.window.views.last.command(CallViewAction.accept));
    await frames(tester);
    f.seed(id: 'replacement');
    await frames(tester);
    final closing = f.command(f.window.views.last.command(CallViewAction.end));
    await frames(tester);
    expect(f.bridge.lastCall(BridgeMethod.callDecline)?.arg<String>('callId'),
        'replacement');
    accepted.complete();
    await tester.pump();
    await Future.wait([accepting, closing]);
    await tester.pumpWidget(const SizedBox.shrink());
    f.container.dispose();
    await tester.pump();
  });

  testWidgets('late incoming decline cannot end the same active call',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    await f.mount(tester);
    final stale = f.window.views.last.command(CallViewAction.decline);
    final oldView = tester.widget<CallView>(find.byType(CallView));
    f.seed(active: true);
    await frames(tester);
    await f.command(stale);
    oldView.onAction(CallViewAction.decline);
    await frames(tester);
    expect(f.bridge.countOf(BridgeMethod.callDecline), 0);
    expect(f.bridge.countOf(BridgeMethod.callEnd), 0);
    expect(find.byTooltip('Mute'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    f.container.dispose();
    await tester.pump();
  });

  for (final outcome in ['accepted', 'failed', 'replaced']) {
    testWidgets('native close waits for accept: $outcome', (tester) async {
      final f = _Fixture();
      addTearDown(f.container.dispose);
      final accepted = Completer<void>();
      f.bridge.respondNext(BridgeMethod.callAccept, accepted.future);
      await f.mount(tester);
      final displayed = f.window.views.last;
      final accepting = f.command(displayed.command(CallViewAction.accept));
      await frames(tester);
      final closing = f.command(displayed.command(CallViewAction.end));
      await frames(tester);
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
      await tester.pump();
      await Future.wait([accepting, closing]);
      await frames(tester);
      expect(f.bridge.countOf(BridgeMethod.callEnd),
          outcome == 'accepted' ? 1 : 0);
      expect(f.bridge.countOf(BridgeMethod.callDecline),
          outcome == 'failed' ? 1 : 0);
      if (outcome == 'replaced') {
        expect(f.window.views.last.callId, 'replacement');
      } else {
        expect(f.window.closes, 1);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      f.container.dispose();
      await tester.pump();
    });
  }
}
