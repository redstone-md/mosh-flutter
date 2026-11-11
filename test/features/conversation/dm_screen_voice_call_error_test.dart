// Integration coverage for active-call audio setup failures: the error must
// use the DM screen's inline ChatErrorBanner without creating a text-send
// retry action.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show conversationCallBindingProvider;
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/features/voice_call/voice_call_binding.dart'
    show voiceCallBinding;
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import '../../support/pump.dart';

SessionSnapshot _activeSnapshot(String sessionId) => SessionSnapshot(
      inviteAvailable: false,
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
        callId: 'call-1',
        direction: 'caller',
        startedAtMs: BigInt.zero,
      ),
    );

void main() {
  testWidgets(
      'active-call audio setup failure shows an app-level error without Retry',
      (tester) async {
    const sessionId = 'sess-voice-error';
    final gateway = ScriptableGateway();
    gateway.seedSessions([_activeSnapshot(sessionId)]);
    final bridge = ScriptableBridge(conversations: gateway.conversations)
      ..failNext(BridgeMethod.nativeCallPrepare,
          error: Exception('audio setup boom'));
    final owner = NativeCallOwner(bridge, () async => true);
    addTearDown(owner.dispose);

    await pumpScreen(
        tester, const VoiceCallHost(child: DmScreen(sessionId: sessionId)),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(bridge),
          activeSessionProvider(sessionId).overrideWith(
            (ref) async => _activeSnapshot(sessionId),
          ),
          nativeCallOwnerProvider.overrideWithValue(owner),
          // A desktop whose call window never opens, so the call stays out
          // of the main window and the chat stays in view.
          callWindowFactoryProvider
              .overrideWithValue((_) => Completer<CallWindowHandle>().future),
          // The error comes out of the call layer, so this screen needs
          // the voice-call module bound to the conversation's call slots.
          conversationCallBindingProvider.overrideWithValue(voiceCallBinding),
        ],
        settle: false);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('audio setup boom'), findsOneWidget);
    final l = AppLocalizations.of(tester.element(find.byType(DmScreen)))!;
    expect(find.text(l.chatErrorRetry), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
