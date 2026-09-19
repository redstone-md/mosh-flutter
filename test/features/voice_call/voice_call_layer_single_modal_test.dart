// The layer owes the user at most one modal per call. These drive the
// transitions a real call goes through (ring -> active, then the 1 s poll
// re-emitting the same active call) and count the routes on screen.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_overlay.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart';
import 'package:mosh/src/features/voice_call/outgoing_call_modal.dart';
import 'package:mosh/src/features/voice_call/voice_call_layer.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show voiceCaptureFactoryProvider;
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

const _sessionId = 'sess-a';

SessionSnapshot _snapshot({
  OutgoingCall? outgoingCall,
  PendingCall? pendingCall,
  ActiveCall? activeCall,
}) =>
    SessionSnapshot(
      sessionId: _sessionId,
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
      outgoingCall: outgoingCall,
      pendingCall: pendingCall,
      activeCall: activeCall,
    );

final _active = ActiveCall(
  callId: 'call-1',
  direction: 'caller',
  keyB64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  noncePrefixB64: 'AAAAAAAAAAA=',
  startedAtMs: BigInt.zero,
);

class _Session {
  SessionSnapshot snapshot = _snapshot();
}

class _NeverCaptureFactory implements VoiceCaptureFactory {
  @override
  bool get isSupported => true;

  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List) onFrame) =>
      Completer<VoiceCaptureHandle>().future;
}

/// Re-emits the session the way the auto-poll does and lets the layer's
/// post-frame open + the dialog route's first build run.
Future<void> _poll(WidgetTester tester, ProviderContainer container) async {
  container.invalidate(activeSessionProvider(_sessionId));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late _Session session;
  late ProviderContainer container;

  setUp(() {
    session = _Session();
    final gateway = ScriptableGateway();
    container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
      activeSessionProvider(_sessionId)
          .overrideWith((ref) => Future.value(session.snapshot)),
      // A capture that never comes up keeps the orchestrator's 20 ms frame
      // poll out of the test's pending-timer check.
      voiceCaptureFactoryProvider.overrideWithValue(_NeverCaptureFactory()),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> pumpLayer(WidgetTester tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await pumpScreen(
      tester,
      Scaffold(body: VoiceCallLayer(sessionId: _sessionId, l: l)),
      container: container,
      settle: false,
    );
    await _poll(tester, container);
  }

  testWidgets('caller: ring -> active -> re-polls shows one overlay',
      (tester) async {
    session.snapshot =
        _snapshot(outgoingCall: const OutgoingCall(callId: 'call-1'));
    await pumpLayer(tester);
    expect(find.byType(OutgoingCallModal), findsOneWidget);

    session.snapshot = _snapshot(activeCall: _active);
    await _poll(tester, container);
    await _poll(tester, container);
    await _poll(tester, container);

    expect(find.byType(OutgoingCallModal), findsNothing);
    expect(find.byType(CallOverlay), findsOneWidget);
  });

  testWidgets('callee: ring -> accept -> active -> re-polls shows one overlay',
      (tester) async {
    session.snapshot = _snapshot(
        pendingCall: const PendingCall(callId: 'call-1', fromDevice: 'Alice'));
    await pumpLayer(tester);
    expect(find.byType(IncomingCallModal), findsOneWidget);

    session.snapshot = _snapshot(activeCall: _active);
    await tester.tap(find.byTooltip(
        (await AppLocalizations.delegate.load(const Locale('en')))
            .callIncomingAccept));
    await _poll(tester, container);
    await _poll(tester, container);
    await _poll(tester, container);

    expect(find.byType(IncomingCallModal), findsNothing);
    expect(find.byType(CallOverlay), findsOneWidget);
  });
}
