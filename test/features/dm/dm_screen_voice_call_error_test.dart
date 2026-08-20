// Integration coverage for active-call audio setup failures: the error must
// use the DM screen's inline ChatErrorBanner without creating a text-send
// retry action.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/features/dm/voice_capture.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import '../../support/pump.dart';

class _FailingCaptureFactory implements VoiceCaptureFactory {
  @override
  bool get isSupported => true;

  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) {
    return Future.error(Exception('audio setup boom'));
  }
}

SessionSnapshot _activeSnapshot(String sessionId) => SessionSnapshot(
      sessionId: sessionId,
      meshId: 'mesh',
      role: 'caller',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: 'connected',
      path: 'direct',
      fingerprint: 'fp',
      messages: const [],
      attachments: const [],
      events: const [],
      activeCall: ActiveCall(
        callId: 'call-1',
        direction: 'caller',
        keyB64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        noncePrefixB64: 'AAAAAAAAAAA=',
        startedAtMs: BigInt.zero,
      ),
    );

void main() {
  testWidgets(
      'active-call audio setup failure renders inline error without Retry',
      (tester) async {
    const sessionId = 'sess-voice-error';
    final gateway = ScriptableGateway();

    await pumpScreen(tester, const DmScreen(sessionId: sessionId),
        overrides: [
          gatewayProvider.overrideWithValue(gateway as Gateway),
          activeSessionProvider(sessionId).overrideWith(
            (ref) async => _activeSnapshot(sessionId),
          ),
          voiceCaptureFactoryProvider
              .overrideWithValue(_FailingCaptureFactory()),
        ],
        settle: false);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('audio setup boom'), findsOneWidget);
    final l = AppLocalizations.of(tester.element(find.byType(DmScreen)))!;
    expect(find.text(l.chatErrorRetry), findsNothing);
    expect(gateway.countOf(GatewayMethod.callEnd), 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
