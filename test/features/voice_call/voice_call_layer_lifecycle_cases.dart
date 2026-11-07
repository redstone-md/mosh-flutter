// Lifecycle coverage for VoiceCallLayer's new error-ownership model:
// the orchestrator is the ONE home for call errors, and the layer only
// decides how to show them -- an audio-setup failure lands in the host
// conversation's error banner (widget.onVoiceCallError) and is recorded in
// the orchestrator state, and clearError drops it once shown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart'
    show kCallDeclineReasonHangup;
import 'package:mosh/src/features/voice_call/voice_call_layer.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';

/// The call engine refusing to prepare media for the active call.
NativeCallOwner _failingMedia(ScriptableBridge bridge, Object error) {
  bridge.failNext(BridgeMethod.nativeCallPrepare, error: error);
  return NativeCallOwner(bridge, () async => true);
}

SessionSnapshot _activeSnapshot(String sessionId) => TestSnapshots.dm(
      sessionId: sessionId,
      meshId: 'mesh',
      role: 'caller',
      peerDisplayName: 'Alice',
      fingerprint: 'fp',
      activeCall: TestCalls.active(callId: 'call-$sessionId'),
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
      'failed setup and failed signaling retain a usable hang-up control',
      (tester) async {
    const sessionId = 'failed-audio';
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.callEnd,
          error: StateError('signaling unavailable'));
    final media = _failingMedia(bridge, StateError('microphone unavailable'));
    addTearDown(media.dispose);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      bridgeFacadeProvider.overrideWithValue(bridge),
      activeSessionProvider(sessionId)
          .overrideWith((ref) async => _activeSnapshot(sessionId)),
      nativeCallOwnerProvider.overrideWithValue(media),
    ]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpLayer(tester,
        container: container, sessionId: sessionId, l: l, onError: (_) {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text(l.callAudioFailed), findsOneWidget);
    final mic = find.descendant(
        of: find.byTooltip(l.callActiveMute),
        matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(mic).onPressed, isNull);
    await tester.tap(find.byTooltip(l.callActiveHangUp));
    await tester.pump();
    expect(bridge.countOf(BridgeMethod.callEnd), 1);
    expect(find.byTooltip(l.callActiveHangUp), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });

  testWidgets(
      'audio-setup failure surfaces via onVoiceCallError and keeps the call',
      (tester) async {
    const sessionId = 'sess-a';
    final errors = <String?>[];
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    final media = _failingMedia(bridge, Exception('boom'));
    addTearDown(media.dispose);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      activeSessionProvider(sessionId)
          .overrideWith((ref) => Future.value(_activeSnapshot(sessionId))),
      nativeCallOwnerProvider.overrideWithValue(media),
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
    // The engine refused to prepare media for this call.
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
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
    // The user ends it: the hang-up control stays usable.
    expect(find.byTooltip(l.callActiveHangUp), findsOneWidget);
  });

  testWidgets('surfaced error is cleared and a second clearError is a no-op',
      (tester) async {
    const sessionId = 'sess-b';
    final errors = <String?>[];
    final bridge = ScriptableBridge();
    final media = _failingMedia(bridge, Exception('boom'));
    addTearDown(media.dispose);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      bridgeFacadeProvider.overrideWithValue(bridge),
      activeSessionProvider(sessionId)
          .overrideWith((ref) => Future.value(_activeSnapshot(sessionId))),
      nativeCallOwnerProvider.overrideWithValue(media),
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
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.callEnd, error: error);
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      bridgeFacadeProvider.overrideWithValue(bridge),
      activeSessionProvider(sessionId)
          .overrideWith((ref) => Future.value(_activeSnapshot(sessionId))),
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
