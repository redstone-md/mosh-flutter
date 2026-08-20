// Lifecycle coverage for VoiceCallLayer's session-scoped error owner.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/call_overlay.dart';
import 'package:mosh/src/features/dm/voice_call_layer.dart';
import 'package:mosh/src/features/dm/voice_capture.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';

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
      state: 'connected',
      path: 'direct',
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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VoiceCallLayer(
            sessionId: sessionId,
            l: l,
            onVoiceCallError: onError,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _closeCallOverlay(WidgetTester tester) async {
  final overlay = find.byType(CallOverlay);
  if (overlay.evaluate().isEmpty) return;
  Navigator.of(tester.element(overlay.first)).pop();
  await tester.pump();
}

void main() {
  testWidgets('dispose clears owner and restores provider fallback',
      (tester) async {
    const sessionId = 'sess-dispose';
    final capture = _DelayedCaptureFactory();
    final ownerErrors = <String?>[];
    final fallbackErrors = <String?>[];
    final gateway = ScriptableGateway();
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      activeSessionProvider(sessionId).overrideWith(
        (ref) async => _activeSnapshot(sessionId),
      ),
      voiceCaptureFactoryProvider.overrideWithValue(capture),
      voiceCallErrorSinkProvider.overrideWithValue(fallbackErrors.add),
    ]);
    addTearDown(container.dispose);

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpLayer(
      tester,
      container: container,
      sessionId: sessionId,
      l: l,
      onError: ownerErrors.add,
    );
    expect(capture.starts, hasLength(1));
    await _closeCallOverlay(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    capture.starts.single.completeError(Exception('late setup failure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(ownerErrors, isEmpty);
    expect(fallbackErrors, contains(contains('late setup failure')));
    expect(gateway.countOf(GatewayMethod.callEnd), 1);
  });

  testWidgets('session change clears old owner and keeps latest callback',
      (tester) async {
    const oldSession = 'sess-old';
    const newSession = 'sess-new';
    final capture = _DelayedCaptureFactory();
    final oldErrors = <String?>[];
    final newErrors = <String?>[];
    final fallbackErrors = <String?>[];
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      activeSessionProvider(oldSession).overrideWith(
        (ref) async => _activeSnapshot(oldSession),
      ),
      activeSessionProvider(newSession).overrideWith(
        (ref) async => _activeSnapshot(newSession),
      ),
      voiceCaptureFactoryProvider.overrideWithValue(capture),
      voiceCallErrorSinkProvider.overrideWithValue(fallbackErrors.add),
    ]);
    addTearDown(container.dispose);
    final oldKeepAlive = container.listen(
      voiceCallOrchestratorProvider(oldSession),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(oldKeepAlive.close);

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpLayer(
      tester,
      container: container,
      sessionId: oldSession,
      l: l,
      onError: oldErrors.add,
    );
    expect(capture.starts, hasLength(1));
    await _closeCallOverlay(tester);

    await _pumpLayer(
      tester,
      container: container,
      sessionId: newSession,
      l: l,
      onError: newErrors.add,
    );
    expect(capture.starts, hasLength(2));
    await _closeCallOverlay(tester);

    capture.starts[0].completeError(Exception('old setup failure'));
    await tester.pump();
    capture.starts[1].completeError(Exception('new setup failure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(oldErrors, isEmpty);
    expect(newErrors, contains(contains('new setup failure')));
    expect(fallbackErrors, contains(contains('old setup failure')));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
