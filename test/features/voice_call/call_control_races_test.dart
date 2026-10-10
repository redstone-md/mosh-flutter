import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
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
  var opened = 0;
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
        pendingCall: active
            ? null
            : PendingCall(
                answerPending: false, callId: id, fromDevice: 'Alice'),
        activeCall: active ? TestCalls.active(callId: id) : null,
      )
    ]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
  }

  Future<void> mount(WidgetTester tester, {bool renderWindow = false}) async {
    seed();
    await pumpScreen(
        tester,
        VoiceCallHost(
            onOpenConversation: (_) => opened++,
            child: Scaffold(
                body: !renderWindow
                    ? null
                    : ValueListenableBuilder<CallViewState?>(
                        valueListenable: window.presentation,
                        builder: (_, call, __) => call == null
                            ? const SizedBox.shrink()
                            : CallView(
                                call: call,
                                onAction: (action) => unawaited(
                                    command(call.command(action))))))),
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

void main() {
  testWidgets('cancel survives an authenticated merge during its control wait',
      (tester) async {
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
    f.gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin',
          pendingCall: const PendingCall(
              callId: 'canonical',
              supersededCallId: 'call',
              fromDevice: 'Alice',
              answerPending: true))
    ]);
    f.container.invalidate(conversationListProvider(ConversationKind.dm));
    await frames(tester);
    accepted.complete();
    await Future.wait([accepting, closing]);
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
    final oldCommand = f.window.views.last.command(CallViewAction.end);
    f.gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin',
          pendingCall: const PendingCall(
              callId: 'canonical',
              supersededCallId: 'original',
              fromDevice: 'Alice',
              answerPending: true))
    ]);
    f.container.invalidate(conversationListProvider(ConversationKind.dm));
    await frames(tester);
    await f.command(oldCommand);
    expect(f.bridge.countOf(BridgeMethod.callEnd), 1);
    expect(f.bridge.lastCall(BridgeMethod.callEnd)?.arg<String>('callId'),
        'canonical');
    expect(f.bridge.countOf(BridgeMethod.callDecline), 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('both call views open the origin while accept is pending',
      (tester) async {
    final f = _Fixture();
    addTearDown(f.container.dispose);
    f.bridge.hold(BridgeMethod.callAccept);
    await f.mount(tester);
    final accepting =
        f.command(f.window.views.last.command(CallViewAction.accept));
    await frames(tester);
    expect(f.window.views.last.busy, isTrue);
    await f
        .command(f.window.views.last.command(CallViewAction.openConversation));
    await tester.tap(find.descendant(
        of: find.byType(CallModalCard),
        matching: find.text(f.window.views.last.peer)));
    await frames(tester);
    expect(f.opened, 2);
    expect(f.bridge.countOf(BridgeMethod.callEnd), 0);
    expect(f.bridge.countOf(BridgeMethod.callDecline), 0);
    f.bridge.release(BridgeMethod.callAccept);
    await accepting;
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
    expect(f.window.views.last.phase, CallViewPhase.active);
    expect(find.byTooltip('Mute'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    f.container.dispose();
    await tester.pump();
  });

  for (final kind in ['native', 'button']) {
    for (final outcome in ['accepted', 'failed', 'replaced']) {
      testWidgets('$kind close waits for accept: $outcome', (tester) async {
        final f = _Fixture();
        addTearDown(f.container.dispose);
        final accepted = Completer<void>();
        f.bridge.respondNext(BridgeMethod.callAccept, accepted.future);
        await f.mount(tester, renderWindow: kind == 'button');
        final displayed = f.window.views.last;
        final accepting = f.command(displayed.command(CallViewAction.accept));
        await frames(tester);
        final Future<void> closing;
        if (kind == 'native') {
          closing = f.command(displayed.command(CallViewAction.end));
        } else {
          await tester.tap(find.byTooltip('Cancel call'));
          closing = Future.value();
        }
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
}
