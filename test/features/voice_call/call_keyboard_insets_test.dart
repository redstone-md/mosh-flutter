import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

void main() {
  for (final withCall in [false, true]) {
    testWidgets('keyboard leaves composer and call controls visible: $withCall',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      final bridge = ScriptableBridge();
      if (withCall) {
        bridge.seedSessions([
          TestSnapshots.dm(
              sessionId: 'origin',
              outgoingCall: const OutgoingCall(callId: 'call'))
        ]);
      }
      const composer = ValueKey('composer');
      await pumpScreen(
          tester,
          const VoiceCallHost(
              child: Scaffold(
                  body: Column(children: [
            Expanded(child: Text('Messages')),
            TextField(key: composer),
          ]))),
          overrides: [bridgeFacadeProvider.overrideWithValue(bridge)],
          settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      for (final keyboardHeight in [250.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        await tester.pump(const Duration(milliseconds: 50));
        final availableBottom = 600 - keyboardHeight;
        final composerRect = tester.getRect(find.byKey(composer));
        if (withCall) {
          final strip = tester.getRect(find.byType(CallModalCard));
          expect(strip.bottom, closeTo(availableBottom, 0.1));
          expect(composerRect.bottom, closeTo(strip.top, 0.1),
              reason: 'The nested Scaffold must not subtract the IME twice');
        } else {
          expect(composerRect.bottom, closeTo(availableBottom, 0.1));
        }
      }
    });
  }

  testWidgets('call admission and termination preserve the composer draft',
      (tester) async {
    final bridge = ScriptableBridge();
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await pumpScreen(
        tester, const VoiceCallHost(child: Scaffold(body: TextField())),
        container: container, settle: false);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'Draft before call');
    for (final withCall in [true, false]) {
      bridge.seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin',
            outgoingCall: withCall ? const OutgoingCall(callId: 'call') : null)
      ]);
      await container
          .read(conversationListProvider(ConversationKind.dm).notifier)
          .refresh();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Draft before call'), findsOneWidget);
    }
  });
}
