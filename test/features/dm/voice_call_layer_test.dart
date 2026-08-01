// Tests for the voice-call wiring seam: `startVoiceCall` routes through the
// `Gateway.callStart` seam, and `VoiceCallLayer` shows the OutgoingCallModal
// when the snapshot reflects an `outgoingCall` (the parity port of React
// private-dm-screen.tsx L479-491).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/voice_call_layer.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// A minimal recording Gateway: only `callStart` + `pollSession` are
/// exercised here; the rest throw UnimplementedError so any other call
/// surface surfaces loudly in the test instead of silently no-opping.
class _RecordingGateway implements Gateway {
  int callStartCount = 0;
  String? lastCallStartSession;
  SessionSnapshot? pollSnapshot;

  @override
  Future<CallStarted> callStart({required String sessionId}) async {
    callStartCount++;
    lastCallStartSession = sessionId;
    return CallStarted(
      sessionId: sessionId,
      callId: 'call-1',
      keyB64: 'k',
      noncePrefixB64: 'n',
    );
  }

  @override
  Future<SessionSnapshot> pollSession({required String sessionId}) async {
    final snap = pollSnapshot;
    if (snap != null) return snap;
    throw UnimplementedError('no snapshot seeded');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

SessionSnapshot _outgoingSnapshot(String sessionId) => SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'caller',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: 'connecting',
      path: 'direct',
      fingerprint: 'fp',
      messages: const [],
      attachments: const [],
      events: const [],
      outgoingCall: const OutgoingCall(callId: 'call-1'),
    );

void main() {
  testWidgets(
    'startVoiceCall routes through gateway.callStart',
    (tester) async {
      final gateway = _RecordingGateway();
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: [gatewayProvider.overrideWithValue(gateway as Gateway)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      ));
      await tester.pump();
      await startVoiceCall(ref, 'sess-1');
      expect(gateway.callStartCount, 1);
      expect(gateway.lastCallStartSession, 'sess-1');
    },
  );

  testWidgets(
    'VoiceCallLayer shows OutgoingCallModal when the snapshot has an outgoingCall',
    (tester) async {
      final gateway = _RecordingGateway();
      gateway.pollSnapshot = _outgoingSnapshot('sess-1');
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(ProviderScope(
        overrides: [gatewayProvider.overrideWithValue(gateway as Gateway)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VoiceCallLayer(sessionId: 'sess-1', l: l),
          ),
        ),
      ));
      // The layer routes the outgoing modal through showDialog; pump a
      // couple frames to let the post-frame callback fire.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Calling...'), findsOneWidget);
    },
  );
}
