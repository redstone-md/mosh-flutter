import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/voice_call_layer.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  testWidgets('a still-rendered cancel button cannot end a replacement call',
      (tester) async {
    var snapshot = TestSnapshots.dm(
        sessionId: 's', outgoingCall: const OutgoingCall(callId: 'first'));
    final bridge = ScriptableBridge();
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      bridgeFacadeProvider.overrideWithValue(bridge),
      activeSessionProvider('s').overrideWith((ref) async => snapshot),
    ]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await pumpScreen(
        tester, Scaffold(body: VoiceCallLayer(sessionId: 's', l: l)),
        container: container, settle: false);
    await tester.pump();
    final old = tester.widget<CallView>(find.byType(CallView));
    snapshot = TestSnapshots.dm(
        sessionId: 's', outgoingCall: const OutgoingCall(callId: 'second'));
    container.invalidate(activeSessionProvider('s'));
    await container.read(activeSessionProvider('s').future);
    expect(container.read(voiceCallOrchestratorProvider('s')).dialog.callId,
        'second');
    old.onAction(CallViewAction.end);
    expect(bridge.countOf(BridgeMethod.callEnd), 0);
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel call'));
    await tester.pump();
    expect(
        bridge.lastCall(BridgeMethod.callEnd)!.arg<String>('callId'), 'second');
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });
}
