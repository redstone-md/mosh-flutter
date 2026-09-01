// Tests for the voice-call wiring seam: `startVoiceCall` routes through the
// `Gateway.callStart` seam, and `VoiceCallLayer` shows the OutgoingCallModal
// when the snapshot reflects an `outgoingCall` (the parity port of React
// private-dm-screen.tsx L479-491).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show MethodChannel;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/voice_call_layer.dart';
import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/notifications_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

SessionSnapshot _pendingSnapshot(String sessionId,
        {String fromDevice = 'Alice'}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'caller',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: 'ringing',
      path: 'direct',
      fingerprint: 'fp',
      messages: const [],
      attachments: const [],
      events: const [],
      pendingCall: PendingCall(callId: 'call-1', fromDevice: fromDevice),
    );

/// A recording fake of the notifications plugin: `show` records (id, title,
/// body) so the incoming-call notification test can assert the OS toast
/// fired. `initialize` is not called here -- the test overrides the
/// notificationsReadyProvider directly to `AsyncValue.data(true)` so the
/// gate opens without running the real init (which needs a platform host).
class _RecordingNotifications implements FlutterLocalNotificationsPlugin {
  int showCalls = 0;
  int? lastId;
  String? lastTitle;
  String? lastBody;
  NotificationDetails? lastDetails;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    showCalls++;
    lastId = id;
    lastTitle = title;
    lastBody = body;
    lastDetails = notificationDetails;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

SessionSnapshot _activeSnapshot(String sessionId) => SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
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
        // Valid 32-byte base64 key + 8-byte nonce prefix so the
        // orchestrator's importCallKey succeeds when it auto-attaches.
        keyB64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        noncePrefixB64: 'AAAAAAAAAAA=',
        startedAtMs: BigInt.zero,
      ),
    );

void main() {
  testWidgets(
    'startVoiceCall routes through gateway.callStart',
    (tester) async {
      final gateway = ScriptableGateway();
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: [gatewayProvider.overrideWithValue(gateway)],
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
      expect(gateway.countOf(GatewayMethod.callStart), 1);
      expect(
          gateway.lastCall(GatewayMethod.callStart)?.arg<String>('sessionId'),
          'sess-1');
    },
  );

  testWidgets(
    'VoiceCallLayer shows OutgoingCallModal when the snapshot has an outgoingCall',
    (tester) async {
      final gateway = ScriptableGateway();
      gateway.seedSessions([_outgoingSnapshot('sess-1')]);
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      // The layer opens the outgoing modal from a post-frame callback,
      // so the pump does not settle -- the next pump lets it open.
      await pumpScreen(
          tester,
          Scaffold(
            body: VoiceCallLayer(sessionId: 'sess-1', l: l),
          ),
          overrides: [gatewayProvider.overrideWithValue(gateway)],
          settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Calling...'), findsOneWidget);
    },
  );

  testWidgets(
    'toggling mute in the active-call overlay flips the orchestrator mute flag',
    (tester) async {
      final gateway = ScriptableGateway();
      gateway.seedSessions([_activeSnapshot('sess-1')]);
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      late WidgetRef ref;
      // Same as above: the active-call overlay opens a frame later.
      await pumpScreen(
          tester,
          Scaffold(
            body: Column(
              children: [
                VoiceCallLayer(sessionId: 'sess-1', l: l),
                Consumer(
                  builder: (context, r, _) {
                    ref = r;
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
          overrides: [gatewayProvider.overrideWithValue(gateway)],
          settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      // The overlay opens with the mic (unmuted) affordance.
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(
        ref.read(voiceCallOrchestratorProvider('sess-1')).muted,
        isFalse,
      );
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      // The toggle hit the orchestrator notifier; the provider state flipped.
      expect(
        ref.read(voiceCallOrchestratorProvider('sess-1')).muted,
        isTrue,
      );
    },
  );

  testWidgets(
    'fires an OS notification for a new incoming call when notifications are ready',
    (tester) async {
      final gateway = ScriptableGateway();
      gateway.seedSessions([_pendingSnapshot('sess-1', fromDevice: 'Alice')]);
      final notifications = _RecordingNotifications();
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      // The voice-call layer's focus check awaits `windowManager.isFocused()`
      // on Windows/macOS hosts. `flutter test` has no window_manager platform
      // impl, so mock the 'window_manager' method channel to report the
      // window as UNFOCUSED (so the gate passes and `show` runs). Harmless on
      // Linux hosts (the channel is never called there -- the layer skips the
      // focus check on Linux).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'),
              (call) async {
        if (call.method == 'isFocused') return false;
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('window_manager'), null));

      // The first frame runs build(), which starts the incoming branch.
      // The next pump lets the post-frame callback open the modal and
      // the fire-and-forget notification call finish.
      await pumpScreen(
          tester,
          Scaffold(
            body: VoiceCallLayer(sessionId: 'sess-1', l: l),
          ),
          overrides: [
            gatewayProvider.overrideWithValue(gateway),
            // Open the gate without running the real plugin init (which needs
            // a platform host absent under `flutter test`).
            notificationsReadyProvider
                .overrideWithValue(const AsyncValue.data(true)),
            // Inject the recording fake so the test can assert `show` fired.
            flutterLocalNotificationsPluginProvider
                .overrideWithValue(notifications),
          ],
          settle: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(notifications.showCalls, 1);
      expect(notifications.lastTitle, 'Mosh');
      expect(notifications.lastBody, 'Incoming call from Alice');
      expect(notifications.lastId, 'Alice'.hashCode.abs());
      expect(
          notifications.lastDetails?.android?.channelId, 'mosh_notifications');
      expect(notifications.lastDetails?.android?.channelName,
          'Mosh notifications');
      // The in-app IncomingCallModal opened too (the toast is additive):
      // the modal shows the peer label + the localized incoming status.
      expect(find.text('Alice'), findsWidgets);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
