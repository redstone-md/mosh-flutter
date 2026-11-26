import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/features/voice_call/call_strip.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';

import '../../support/message_builders.dart';
import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

/// A phone: the call shows in the main window, which has no title bar.
Future<ScriptableBridge> _phone(
    WidgetTester tester, SessionSnapshot session) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.reset);
  mockCallVideoPlugin(tester);
  final gateway = ScriptableGateway()..seedSessions([session]);
  final bridge = ScriptableBridge(conversations: gateway.conversations);
  final owner = NativeCallOwner(bridge, () async => true);
  // The call host listens for Back, which needs the router.
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => const VoiceCallHost(
            child: Scaffold(
                body:
                    Align(alignment: Alignment.topCenter, child: TextField()))))
  ]);
  addTearDown(router.dispose);
  await pumpScreen(tester,
      ReleasesCallMedia(media: owner, child: Router.withConfig(config: router)),
      overrides: <Override>[
        gatewayProvider.overrideWithValue(gateway),
        bridgeFacadeProvider.overrideWithValue(bridge),
        nativeCallOwnerProvider.overrideWithValue(owner),
      ],
      settle: false);
  await tester.pump(const Duration(milliseconds: 100));
  return bridge;
}

Future<void> _plate(WidgetTester tester, CallViewState call,
        {List<CallViewAction>? actions, VoidCallback? onOpen}) =>
    pumpScreen(
        tester,
        Scaffold(
            body: Center(
                child: CallView(
                    call: call,
                    form: CallForm.plate,
                    now: () => 5000,
                    onOpen: onOpen,
                    onAction: (action) => actions?.add(action)))),
        settle: false);

const _active = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active,
    audioReady: true);

void main() {
  testWidgets(
      'on the phone a minimized call is a strip above the screen, which '
      'keeps its state as the call opens and folds', (tester) async {
    await _phone(
        tester,
        TestSnapshots.dm(
            sessionId: 'origin',
            outgoingCall: const OutgoingCall(callId: 'call')));
    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();

    final strip = tester.getRect(find.byType(CallStrip));
    expect(tester.getRect(find.byType(TextField)).top, strip.bottom,
        reason: 'the strip moves the screen down and covers none of it');
    await tester.enterText(find.byType(TextField), 'draft');

    await tester.tap(find.byTooltip('Expand call'));
    await tester.pump();
    expect(find.byType(CallStrip), findsNothing);
    expect(find.byType(TextField).hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();

    expect(find.text('draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a call minimized while it rings is answered from the strip',
      (tester) async {
    final bridge = await _phone(
        tester,
        TestSnapshots.dm(
            sessionId: 'origin',
            pendingCall: const PendingCall(
                callId: 'call', fromDevice: 'Alice', answerPending: false)));
    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();

    await tester.tap(find.byTooltip('Accept call'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(bridge.lastCall(BridgeMethod.callAccept)!.arg<String>('callId'),
        'call');
    expect(find.byType(TextField).hitTestable(), findsOneWidget,
        reason: 'answering from the strip does not open the call');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a call minimized while it rings is declined from the strip',
      (tester) async {
    final bridge = await _phone(
        tester,
        TestSnapshots.dm(
            sessionId: 'origin',
            pendingCall: const PendingCall(
                callId: 'call', fromDevice: 'Alice', answerPending: false)));
    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();

    await tester.tap(find.byTooltip('Decline call'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(bridge.lastCall(BridgeMethod.callDecline)!.arg<String>('callId'),
        'call');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the plate says a muted call is muted beside its time',
      (tester) async {
    await _plate(
        tester,
        const CallViewState(
            sessionId: 'dm',
            callId: 'call',
            peer: 'Alice',
            phase: CallViewPhase.active,
            audioReady: true,
            muted: true));
    expect(find.text('0:05 · Muted'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a warning takes the place of the time on the plate',
      (tester) async {
    await _plate(
        tester,
        const CallViewState(
            sessionId: 'dm',
            callId: 'call',
            peer: 'Alice',
            phase: CallViewPhase.active,
            audioReady: true,
            occupancyConflict: true));
    expect(find.textContaining('Calls are active on different devices'),
        findsOneWidget);
    expect(find.textContaining('0:05'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'on the plate the name opens the call and the buttons only do '
      'their own work', (tester) async {
    final actions = <CallViewAction>[];
    var opened = 0;
    await _plate(tester, _active, actions: actions, onOpen: () => opened++);

    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Hang up'));
    expect(actions, [CallViewAction.mute, CallViewAction.end]);
    expect(opened, 0);

    await tester.tap(find.text('Alice'));
    expect(opened, 1);
    expect(actions, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
