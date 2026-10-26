import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import '../support/message_builders.dart';
import '../support/scriptable_bridge.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.mosh.mosh/waiting');

  test(
      'Android Answer serializes permission and a refusal keeps call controls usable',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {
              'revision': 1,
              'intentRevision': 1,
              'interactive': false,
              'callInteractive': true,
              'waitingEnabled': false,
              'serviceRunning': false,
              'setupComplete': true,
              'notificationsAllowed': true,
              'batteryExempt': false,
            });
    final platform = AndroidWaitingPlatform();
    await platform.refresh();
    final waiting = AndroidWaitingOwner(platform, BackgroundCommands());
    final snapshot = TestSnapshots.dm(
        sessionId: 'origin',
        pendingCall: const PendingCall(
            answerPending: false, callId: 'call', fromDevice: 'Alice'));
    waiting.calls.snapshot = snapshot;
    final bridge = ScriptableBridge()..seedSessions([snapshot]);
    final permission = Completer<bool>();
    var prompts = 0;
    final media = NativeCallOwner(bridge, () {
      prompts++;
      return permission.future;
    });
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      androidWaitingOwnerProvider.overrideWithValue(waiting),
      nativeCallOwnerProvider.overrideWithValue(media),
    ]);
    final provider = voiceCallOrchestratorProvider('origin');
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(() {
      subscription.close();
      container.dispose();
      media.dispose();
      waiting.dispose();
      platform.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    final notifier = container.read(provider.notifier);
    final first = notifier.acceptCall('call');
    final second = notifier.acceptCall('call');
    expect(prompts, 1);
    expect(container.read(provider).busy, true);
    permission.complete(false);
    await Future.wait([first, second]);
    expect(bridge.countOf(BridgeMethod.callAccept), 0);
    expect(container.read(provider).busy, false);
    expect(container.read(provider).dialog.callId, 'call');
    expect(bridge.countOf(BridgeMethod.nativeCallChoices), 0);
  });
}
