import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/voice_call_fakes.dart';
import '../../support/settings.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets('the shared strip stays inside phone system insets',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding =
        const FakeViewPadding(bottom: 34, left: 18, right: 16);
    addTearDown(tester.view.reset);
    final gateway = ScriptableGateway()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin',
            outgoingCall: const OutgoingCall(callId: 'call'))
      ]);
    await pumpScreen(tester, const VoiceCallHost(child: Scaffold()),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations)),
        ],
        settle: false);
    await _frames(tester);
    final rect = tester.getRect(find.byType(CallModalCard));
    expect(rect.left, greaterThanOrEqualTo(18));
    expect(rect.right, lessThanOrEqualTo(800 - 16));
    expect(rect.bottom, lessThanOrEqualTo(600 - 34));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'navigation preserves one audio owner and controls the original DM',
      (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    final active = TestSnapshots.dm(
        sessionId: 'origin',
        peerDisplayName: 'Alice',
        activeCall: TestCalls.active(callId: 'original-call'));
    gateway.seedSessions([active, TestSnapshots.dm(sessionId: 'other')]);
    bridge.seedChannels([
      TestSnapshots.channel(
          name: 'room', deviceFingerprint: 'SELF', messages: [])
    ]);
    bridge.seedGroups([
      TestSnapshots.group(
          groupId: 'group', deviceFingerprint: 'SELF', messages: [])
    ]);
    final capture = RecordingCapture();
    final playback = RecordingPlayback();
    final window = RecordingCallWindow();
    var windows = 0;
    late Future<void> Function(CallViewCommand) command;
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      voiceCaptureFactoryProvider.overrideWithValue(capture),
      voicePlaybackFactoryProvider.overrideWithValue(playback),
      callWindowFactoryProvider.overrideWithValue((handler) async {
        windows++;
        command = handler;
        return window;
      }),
    ]);
    addTearDown(container.dispose);
    final router = await pumpRoute(
      tester,
      AppRoutes.dmFor('origin'),
      container: container,
      settle: false,
      builder: (_, child) => VoiceCallHost(child: child!),
    );
    addTearDown(router.dispose);
    await _frames(tester);
    expect(capture.starts, 1);
    expect(playback.starts, 1);
    expect(windows, 1);
    expect(jsonEncode(window.views.last.toMap()),
        isNot(contains(active.activeCall!.keyB64)));

    for (final route in [
      AppRoutes.dmFor('other'),
      AppRoutes.groupFor('group'),
      AppRoutes.channelFor('room'),
      AppRoutes.settings,
      AppRoutes.dmFor('origin')
    ]) {
      if (route == AppRoutes.settings) {
        unawaited(router.push<void>(route));
      } else {
        router.go(route);
      }
      await _frames(tester);
      expect(find.byTooltip('Mute'), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(capture.starts, 1);
      expect(playback.starts, 1);
      expect(capture.stops, 0);
      expect(window.closes, 0);
    }
    await command(window.views.last.command(CallViewAction.mute));
    await _frames(tester);
    expect(find.byTooltip('Unmute'), findsNothing);
    expect(window.views.last.muted, isTrue);
    await command(window.views.last.command(CallViewAction.end));
    await _frames(tester);
    expect(bridge.lastCall(BridgeMethod.callEnd)!.arg<String>('sessionId'),
        'origin');
    expect(bridge.lastCall(BridgeMethod.callEnd)!.arg<String>('callId'),
        'original-call');
    expect(capture.stops, 1);
    expect(playback.stops, 1);
    expect(window.closes, 1);
    expect(find.byTooltip('Mute'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'remote end and a delayed accept cannot revive old controls or ringtone',
      (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations)
      ..hold(BridgeMethod.callAccept);
    gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin',
          pendingCall: const PendingCall(
              answerPending: false, callId: 'first', fromDevice: 'Alice'))
    ]);
    final ring = RecordingRingtone();
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      ringtonePlayerProvider.overrideWithValue(ring),
    ]);
    addTearDown(container.dispose);
    await pumpScreen(
        tester, const VoiceCallHost(child: Scaffold(body: Text('Settings'))),
        container: container, settle: false);
    await _frames(tester);
    expect(ring.starts, 1);
    await tester.tap(find.byTooltip('Accept call'));
    await _frames(tester);
    expect(ring.stops, 1);
    gateway.seedSessions([TestSnapshots.dm(sessionId: 'origin')]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
    await _frames(tester);
    expect(find.byTooltip('Accept call'), findsNothing);
    gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin',
          outgoingCall: const OutgoingCall(callId: 'second'))
    ]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
    await _frames(tester);
    expect(ring.starts, 2);
    bridge.release(BridgeMethod.callAccept);
    await _frames(tester);
    expect(find.text('Calling...'), findsOneWidget);
    expect(ring.stops, 1);
    await tester.tap(find.byTooltip('Cancel call'));
    await _frames(tester);
    expect(ring.stops, 2);
    expect(
        bridge.lastCall(BridgeMethod.callEnd)!.arg<String>('callId'), 'second');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('window startup after a call ended never presents obsolete controls',
      () async {
    final pending = Completer<CallWindowHandle>();
    final window = RecordingCallWindow();
    final coordinator = CallWindowCoordinator(
        (_) => pending.future, (_) async {}, (error) => fail('$error'));
    coordinator.update(const CallViewState(
        sessionId: 's',
        callId: 'c',
        peer: 'Alice',
        phase: CallViewPhase.outgoing));
    coordinator.update(null);
    pending.complete(window);
    await coordinator.dispose();
    expect(window.views, isEmpty);
    expect(window.closes, 1);
  });
}
