import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';
import '../support/message_builders.dart';
import '../support/scriptable_bridge.dart';

class _Fixture {
  final bridge = ScriptableBridge();
  late final container = ProviderContainer(overrides: [
    bridgeFacadeProvider.overrideWithValue(bridge),
  ]);

  Future<String?> select(List<SessionSnapshot> sessions) async {
    bridge.seedSessions(sessions);
    await container
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh();
    return container.read(voiceCallSessionProvider)?.sessionId;
  }
}

void main() {
  final incoming = TestSnapshots.dm(
      sessionId: 'incoming',
      pendingCall: const PendingCall(
          answerPending: false, callId: 'ring', fromDevice: 'Alice'));
  final active = TestSnapshots.dm(
      sessionId: 'active', activeCall: TestCalls.active(callId: 'talk'));

  test('initial selection prefers an active call over an earlier incoming call',
      () async {
    final f = _Fixture();
    addTearDown(() => f.container.dispose());
    expect(await f.select([incoming, active]), 'active');
  });

  test(
      'an existing incoming owner remains selected when another call is active',
      () async {
    final f = _Fixture();
    addTearDown(() => f.container.dispose());
    expect(await f.select([incoming]), 'incoming');
    expect(await f.select([active, incoming]), 'incoming');
  });

  test('promotion prefers an active call after the original owner ends',
      () async {
    final f = _Fixture();
    addTearDown(() => f.container.dispose());
    final original = TestSnapshots.dm(
        sessionId: 'original',
        outgoingCall: const OutgoingCall(callId: 'dial'));
    expect(await f.select([original]), 'original');
    expect(await f.select([incoming, active]), 'active');
    expect(await f.select([]), isNull);
    expect(await f.select([incoming]), 'incoming');
  });
}
