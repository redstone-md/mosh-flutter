import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/voice_call_fakes.dart';

void main() {
  for (final incoming in [false, true]) {
    testWidgets('the ready call window owns controls: incoming=$incoming',
        (tester) async {
      final gateway = ScriptableGateway()
        ..seedSessions([
          TestSnapshots.dm(
              sessionId: 'origin',
              outgoingCall:
                  incoming ? null : const OutgoingCall(callId: 'call'),
              pendingCall: incoming
                  ? const PendingCall(
                      callId: 'call', fromDevice: 'Alice', answerPending: false)
                  : null)
        ]);
      final ready = Completer<CallWindowHandle>();
      await pumpScreen(tester, const VoiceCallHost(child: Scaffold()),
          overrides: [
            gatewayProvider.overrideWithValue(gateway),
            bridgeFacadeProvider.overrideWithValue(
                ScriptableBridge(conversations: gateway.conversations)),
            callWindowFactoryProvider.overrideWithValue((_) => ready.future),
          ],
          settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      final end = incoming ? 'Decline call' : 'Cancel call';
      expect(find.byTooltip(end), findsOneWidget,
          reason: 'controls remain usable until the child is ready');
      ready.complete(RecordingCallWindow());
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip(end), findsNothing);
      expect(find.byTooltip('Accept call'), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a failed call window leaves inline controls usable',
      (tester) async {
    final gateway = ScriptableGateway()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin',
            outgoingCall: const OutgoingCall(callId: 'call'))
      ]);
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    await pumpScreen(tester, const VoiceCallHost(child: Scaffold()),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(bridge),
          callWindowFactoryProvider
              .overrideWithValue((_) async => throw StateError('child failed')),
        ],
        settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Cancel call'));
    await tester.pump();
    expect(
        bridge.lastCall(BridgeMethod.callEnd)?.arg<String>('callId'), 'call');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('controls transfer after presentation and return on its failure',
      (tester) async {
    final gateway = ScriptableGateway()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin',
            outgoingCall: const OutgoingCall(callId: 'call'))
      ]);
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    final presented = Completer<void>();
    final window = RecordingCallWindow()..presentWait = presented.future;
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      callWindowFactoryProvider.overrideWithValue((_) async => window),
    ]);
    addTearDown(container.dispose);
    await pumpScreen(tester, const VoiceCallHost(child: Scaffold()),
        container: container, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Cancel call'), findsOneWidget);
    presented.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Cancel call'), findsNothing);
    window.presentFailure = StateError('renderer exited');
    gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin',
          peerDisplayName: 'Updated',
          outgoingCall: const OutgoingCall(callId: 'call'))
    ]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byTooltip('Cancel call'), findsOneWidget);
    expect(window.closes, 1);
    await tester.tap(find.byTooltip('Cancel call'));
    await tester.pump();
    expect(
        bridge.lastCall(BridgeMethod.callEnd)?.arg<String>('callId'), 'call');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
