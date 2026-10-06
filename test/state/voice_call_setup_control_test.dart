import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart';
import 'package:mosh/src/features/voice_call/voice_call_orchestrator.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import '../support/message_builders.dart';
import '../support/scriptable_bridge.dart';

class _BrokenCapture extends NoopVoiceCaptureFactory {
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List) onFrame) async =>
      throw StateError('capture failed');
}

void main() {
  test('setup-failure hang-up waits for the same call accept', () async {
    final bridge = ScriptableBridge()
      ..hold(BridgeMethod.callAccept)
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin',
            pendingCall: PendingCall(callId: 'call', fromDevice: 'Alice'))
      ]);
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      voiceCaptureFactoryProvider.overrideWithValue(_BrokenCapture()),
    ]);
    addTearDown(container.dispose);
    final provider = voiceCallOrchestratorProvider('origin');
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final accepting = container.read(provider.notifier).acceptCall('call');
    expect(bridge.countOf(BridgeMethod.callAccept), 1);
    bridge.seedSessions([
      TestSnapshots.dm(
          sessionId: 'origin', activeCall: TestCalls.active(callId: 'call'))
    ]);
    container.invalidate(conversationListProvider(ConversationKind.dm));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(provider).error?.source, CallErrorSource.audioSetup);
    expect(bridge.countOf(BridgeMethod.callEnd), 0);
    bridge.release(BridgeMethod.callAccept);
    await accepting;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bridge.countOf(BridgeMethod.callEnd), 1);
    expect(bridge.lastCall(BridgeMethod.callEnd)?.arg<String>('reason'),
        kSetupFailedReason);
    expect(container.read(provider).busy, isFalse);
    expect(container.read(provider).error?.source, CallErrorSource.audioSetup);
  });

  test('manual hang-up joins an automatic setup-failure end', () async {
    final bridge = ScriptableBridge()
      ..hold(BridgeMethod.callEnd)
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'origin', activeCall: TestCalls.active(callId: 'call'))
      ]);
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      voiceCaptureFactoryProvider.overrideWithValue(_BrokenCapture()),
    ]);
    addTearDown(container.dispose);
    final provider = voiceCallOrchestratorProvider('origin');
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bridge.countOf(BridgeMethod.callEnd), 1);
    final ending = container
        .read(provider.notifier)
        .endCall('call', kCallDeclineReasonHangup);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.countOf(BridgeMethod.callEnd), 1);
    expect(container.read(provider).busy, isTrue);
    bridge.release(BridgeMethod.callEnd);
    await ending;
    expect(bridge.countOf(BridgeMethod.callEnd), 1);
    expect(container.read(provider).error?.source, CallErrorSource.audioSetup);
  });
}
