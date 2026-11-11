import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import '../../support/native_call_fixture.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/pump_route.dart';
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
      'navigation preserves one media owner and controls the original DM',
      (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations)
      ..seedNativeCallSnapshot(nativeCallSnapshot(
          sessionId: 'origin', callId: 'original-call', microphone: true));
    final media = NativeCallOwner(bridge, () async => true);
    addTearDown(media.dispose);
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
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      ...settingsCameraOverrides(),
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      nativeCallOwnerProvider.overrideWithValue(media),
    ]);
    addTearDown(container.dispose);
    final router = await pumpRoute(
      tester,
      AppRoutes.dmFor('origin'),
      container: container,
      settle: false,
    );
    await _frames(tester);
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
    await tester.tap(find.byTooltip('Minimize call'));
    await _frames(tester);

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
      expect(find.byTooltip('Hang up'), findsOneWidget,
          reason: 'the mini view follows the user to $route');
      expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
      expect(media.session?.callId, 'original-call');
    }
    await tester.tap(find.byTooltip('Expand call'));
    await _frames(tester);
    await tester.tap(find.byTooltip('Mute'));
    await _frames(tester);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    await tester.tap(find.byTooltip('Hang up'));
    await _frames(tester);
    expect(bridge.lastCall(BridgeMethod.callEnd)!.arg<String>('sessionId'),
        'origin');
    expect(bridge.lastCall(BridgeMethod.callEnd)!.arg<String>('callId'),
        'original-call');
    expect(media.session, isNull);
    expect(find.byTooltip('Mute'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
}
