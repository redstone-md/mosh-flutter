import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/voice_call/android_call_presentation.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

void main() {
  testWidgets('locked call UI and PiP reveal a name only with consent',
      (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    var revision = 0, consent = false;
    messenger.setMockMethodCallHandler(
        AndroidWaitingPlatform.channel,
        (_) async => {
              'revision': ++revision,
              'intentRevision': 1,
              'interactive': false,
              'callInteractive': true,
              'waitingEnabled': true,
              'serviceRunning': true,
              'setupComplete': true,
              'notificationsAllowed': true,
              'batteryExempt': false,
              'showNamesWhenLocked': consent
            });
    messenger.setMockMethodCallHandler(
        AndroidAppAccess.channel,
        (_) async => {
              'version': 1,
              'revision': 1,
              'shieldGeneration': 1,
              'delaySeconds': 60,
              'bootCount': 1,
              'deadlineElapsedMs': 61000,
              'state': 'grace',
              'deviceInteractive': true,
              'allowed': true,
              'callOnly': true
            });
    messenger.setMockMethodCallHandler(
        AndroidCallPresentation.channel, (_) async => null);
    final platform = AndroidWaitingPlatform();
    await platform.refresh();
    final access = AndroidAppAccess();
    await access.initialize();
    final waiting = AndroidWaitingOwner(platform, BackgroundCommands());
    final snapshot = TestSnapshots.dm(
        sessionId: 'dm',
        peerDisplayName: 'Protected caller',
        pendingCall: const PendingCall(
            callId: 'call',
            fromDevice: 'Protected caller',
            answerPending: false));
    waiting.calls.snapshot = snapshot;
    final bridge = ScriptableBridge()..seedSessions([snapshot]);
    final media = NativeCallOwner(bridge, () async => true);
    final presentation = AndroidCallPresentation();
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      nativeCallOwnerProvider.overrideWithValue(media),
      androidWaitingOwnerProvider.overrideWithValue(waiting),
      androidAppAccessProvider.overrideWithValue(access),
      androidCallPresentationProvider.overrideWithValue(presentation),
    ]);
    var disposed = false;
    Future<void> cleanup() async {
      if (disposed) return;
      disposed = true;
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      media.dispose();
      presentation.dispose();
      waiting.dispose();
      platform.dispose();
      access.dispose();
      for (final channel in [
        AndroidWaitingPlatform.channel,
        AndroidAppAccess.channel,
        AndroidCallPresentation.channel
      ]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    }

    addTearDown(cleanup);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const VoiceCallHost(
              child: Scaffold(body: Text('Protected messages'))))
    ]);
    addTearDown(router.dispose);
    await pumpScreen(tester, Router.withConfig(config: router),
        container: container, settle: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Protected caller'), findsNothing);
    expect(find.text('Mosh'), findsOneWidget);
    expect(find.text('Protected messages'), findsNothing);
    expect(presentation.call?.peer, 'Mosh');
    expect(bridge.countOf(BridgeMethod.callAccept), 0);
    consent = true;
    await platform.refresh();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Protected caller'), findsOneWidget);
    expect(presentation.call?.peer, 'Protected caller');
    expect(find.text('Protected messages'), findsNothing);
    expect(access.state!.state, 'grace');
    await cleanup();
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
