// Lifecycle coverage for VoiceCallLayer's new error-ownership model:
// the orchestrator is the ONE home for call errors, and the layer only
// decides how to show them -- an audio-setup failure lands in the host
// conversation's error banner (widget.onVoiceCallError) and is recorded in
// the orchestrator state, and clearError drops it once shown.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart'
    show kCallDeclineReasonHangup;
import 'package:mosh/src/features/voice_call/voice_call_layer.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import '../../support/pump.dart';

class _DelayedCaptureFactory implements VoiceCaptureFactory {
  final List<Completer<VoiceCaptureHandle>> starts = [];

  @override
  bool get isSupported => true;

  @override
  Future<VoiceCaptureHandle> start(
    void Function(Uint8List opusFrame) onFrame,
  ) {
    final start = Completer<VoiceCaptureHandle>();
    starts.add(start);
    return start.future;
  }
}

SessionSnapshot _activeSnapshot(String sessionId) => SessionSnapshot(
      sessionId: sessionId,
      meshId: 'mesh',
      role: 'caller',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      fingerprint: 'fp',
      messages: const [],
      attachments: const [],
      events: const [],
      activeCall: ActiveCall(
        callId: 'call-$sessionId',
        direction: 'caller',
        keyB64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        noncePrefixB64: 'AAAAAAAAAAA=',
        startedAtMs: BigInt.zero,
      ),
    );

Future<void> _pumpLayer(
  WidgetTester tester, {
  required ProviderContainer container,
  required String sessionId,
  required AppLocalizations l,
  required void Function(String? message) onError,
}) async {
  await pumpScreen(
      tester,
      Scaffold(
        body: VoiceCallLayer(
          sessionId: sessionId,
          l: l,
          onVoiceCallError: onError,
        ),
      ),
      container: container,
      settle: false);
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
      'audio-setup failure surfaces via onVoiceCallError and tears the call down',
      (tester) async {
    const sessionId = 'sess-a';
    final capture = _DelayedCaptureFactory();
    final errors = <String?>[];
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      activeSessionProvider(sessionId)
          .overrideWith((ref) => Future.value(_activeSnapshot(sessionId))),
      voiceCaptureFactoryProvider.overrideWithValue(capture),
    ]);
    addTearDown(container.dispose);

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpLayer(
      tester,
      container: container,
      sessionId: sessionId,
      l: l,
      onError: errors.add,
    );
    // The call attached and started capture.
    expect(capture.starts, hasLength(1));

    // The capture that started for this call fails to set up.
    capture.starts.single.completeError(Exception('boom'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // The failure reaches the host conversation's error banner.
    expect(errors, contains(contains('boom')));
    // The layer surfaced the one owned error and cleared it, so it does
    // not linger in orchestrator state.
    expect(
      container.read(voiceCallOrchestratorProvider(sessionId)).error,
      isNull,
    );
    // The dead call is torn down.
    expect(bridge.countOf(BridgeMethod.callEnd), 1);
  });

  testWidgets('surfaced error is cleared and a second clearError is a no-op',
      (tester) async {
    const sessionId = 'sess-b';
    final capture = _DelayedCaptureFactory();
    final errors = <String?>[];
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      bridgeFacadeProvider.overrideWithValue(ScriptableBridge()),
      activeSessionProvider(sessionId)
          .overrideWith((ref) => Future.value(_activeSnapshot(sessionId))),
      voiceCaptureFactoryProvider.overrideWithValue(capture),
    ]);
    addTearDown(container.dispose);

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpLayer(
      tester,
      container: container,
      sessionId: sessionId,
      l: l,
      onError: errors.add,
    );
    capture.starts.single.completeError(Exception('boom'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // Surfaced exactly once to the host, then cleared from state.
    expect(errors, hasLength(1));
    expect(
      container.read(voiceCallOrchestratorProvider(sessionId)).error,
      isNull,
    );

    // Clearing again with nothing pending is a no-op (no throw, no
    // re-surface).
    container
        .read(voiceCallOrchestratorProvider(sessionId).notifier)
        .clearError();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      container.read(voiceCallOrchestratorProvider(sessionId)).error,
      isNull,
    );
    expect(errors, hasLength(1));
  });

  testWidgets("a failed call control is worded by the bridge error's kind",
      (tester) async {
    const sessionId = 'sess-c';
    const error = ConversationBridgeError(
      kind: ConversationBridgeErrorKind.unavailable,
      message: 'dm runtime unavailable: node down',
    );
    final capture = _DelayedCaptureFactory();
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.callEnd, error: error);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      bridgeFacadeProvider.overrideWithValue(bridge),
      activeSessionProvider(sessionId)
          .overrideWith((ref) => Future.value(_activeSnapshot(sessionId))),
      voiceCaptureFactoryProvider.overrideWithValue(capture),
    ]);
    addTearDown(container.dispose);

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpLayer(
      tester,
      container: container,
      sessionId: sessionId,
      l: l,
      onError: (_) => fail('a call-control failure is a snack bar'),
    );

    await container
        .read(voiceCallOrchestratorProvider(sessionId).notifier)
        .endCall('call-$sessionId', kCallDeclineReasonHangup);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text(l.chatActionErrorUnavailable), findsOneWidget);
    expect(find.textContaining(error.message), findsNothing);
  });
}
