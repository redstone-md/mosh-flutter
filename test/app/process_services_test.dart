import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/process_services.dart';
import 'package:mosh/src/platform/ios_system_calls.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';

const _channel = MethodChannel('app.mosh/system-calls');

class _Ringing extends VoiceCallSessionNotifier {
  @override
  SessionSnapshot? build() => SessionSnapshot(
        inviteAvailable: false,
        sessionId: 's',
        meshId: 'm',
        role: 'bob',
        displayName: 'me',
        peerDisplayName: 'Alice',
        state: DmSessionState.connected,
        transport: PeerTransport.direct,
        inviteUri: null,
        fingerprint: 'AA',
        messages: const [],
        attachments: const [],
        mesh: null,
        events: const [],
        pendingCall: const PendingCall(
            callId: 'c', fromDevice: 'Alice', answerPending: false),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A woken iPhone has no window: nothing but the container starts the
  // services, exactly as main() does.
  test('a call reaches the system call screen with no widget built', () async {
    final asked = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      asked.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    final container = ProviderContainer(overrides: [
      iosSystemCallsProvider.overrideWith((ref) => IosSystemCalls()),
      voiceCallSessionProvider.overrideWith(_Ringing.new),
    ]);
    addTearDown(container.dispose);

    container.listen(processServicesProvider, (_, __) {});
    await pumpEventQueue();

    final shown = asked.where((call) => call.method == 'show').single;
    expect(shown.arguments, {'call': 'c', 'kind': 'incoming', 'name': 'Alice'});
  });
}
