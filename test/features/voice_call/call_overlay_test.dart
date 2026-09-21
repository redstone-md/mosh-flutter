// Widget tests for `CallOverlay` (lib/src/features/voice_call/call_overlay.dart).
// The overlay reads its mute
// flag from the orchestrator (the one home for call state) and toggles it
// there, so these tests mount the orchestrator provider (seeded with an
// active call) and assert the icon + tint swap from the live provider state.
//
// Also asserts the mute/hang-up buttons fire, the duration timer renders
// m:ss from `startedAtMs`, and Esc fires onHangUp.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_overlay.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show voiceCallOrchestratorProvider;
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

ActiveCall _active({required int startedAtMs}) => ActiveCall(
      callId: 'call-1',
      direction: 'caller',
      keyB64: 'k',
      noncePrefixB64: 'n',
      startedAtMs: BigInt.from(startedAtMs),
    );

/// An active-session snapshot seeded so the orchestrator attaches and reports
/// `muted: false` until a test flips it via `toggleMute`.
SessionSnapshot _activeSession(String sessionId) => SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'caller',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      fingerprint: 'fp',
      messages: const [],
      attachments: const [],
      events: const [],
      activeCall: _active(startedAtMs: 0),
    );

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Builds a container that wires the orchestrator for [sessionId] with an
/// active call so the overlay can read its (live) mute flag.
ProviderContainer _containerFor(String sessionId) =>
    ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(ScriptableBridge()),
      activeSessionProvider(sessionId)
          .overrideWith((ref) => Future.value(_activeSession(sessionId))),
    ]);

Future<void> _pump(
  WidgetTester tester, {
  required CallOverlay overlay,
  required ProviderContainer container,
}) =>
    pumpScreen(
      tester,
      Scaffold(body: overlay),
      container: container,
    );

void main() {
  testWidgets(
    'mute button toggles the orchestrator mute flag + shows the mic icon when not muted',
    (tester) async {
      final container = _containerFor('call-1');
      addTearDown(container.dispose);
      const sessionId = 'call-1';
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          sessionId: sessionId,
          onHangUp: () {},
          l: await _l(),
        ),
        container: container,
      );
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(
        container.read(voiceCallOrchestratorProvider(sessionId)).muted,
        isFalse,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      // The toggle hit the orchestrator notifier; the icon swaps live.
      expect(
        container.read(voiceCallOrchestratorProvider(sessionId)).muted,
        isTrue,
      );
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
    },
  );

  testWidgets(
    'hang-up button fires onHangUp',
    (tester) async {
      var hangUpCount = 0;
      final container = _containerFor('call-1');
      addTearDown(container.dispose);
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          sessionId: 'call-1',
          onHangUp: () => hangUpCount++,
          l: await _l(),
        ),
        container: container,
      );
      await tester.tap(find.byIcon(Icons.phone_disabled));
      expect(hangUpCount, 1);
    },
  );

  testWidgets(
    'Esc fires onHangUp',
    (tester) async {
      var hangUpCount = 0;
      final container = _containerFor('call-1');
      addTearDown(container.dispose);
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          sessionId: 'call-1',
          onHangUp: () => hangUpCount++,
          l: await _l(),
        ),
        container: container,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(hangUpCount, 1);
    },
  );

  testWidgets(
    'renders the peer label + a 0:00 timer at the start',
    (tester) async {
      final container = _containerFor('call-1');
      addTearDown(container.dispose);
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          sessionId: 'call-1',
          onHangUp: () {},
          now: () => 0,
          l: await _l(),
        ),
        container: container,
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
    },
  );

  testWidgets(
    'renders 1:05 for a 65-second elapsed call',
    (tester) async {
      final container = _containerFor('call-1');
      addTearDown(container.dispose);
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          sessionId: 'call-1',
          onHangUp: () {},
          now: () => 65000,
          l: await _l(),
        ),
        container: container,
      );
      expect(find.text('1:05'), findsOneWidget);
    },
  );

  testWidgets(
    'muted state (set via orchestrator) swaps the icon to mic_off',
    (tester) async {
      const sessionId = 'call-1';
      final container = _containerFor(sessionId);
      addTearDown(container.dispose);
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          sessionId: sessionId,
          onHangUp: () {},
          l: await _l(),
        ),
        container: container,
      );
      // Reflect the toggled mute from the single source of truth.
      container
          .read(voiceCallOrchestratorProvider(sessionId).notifier)
          .toggleMute();
      await tester.pump();
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
    },
  );

  test('formatCallClock renders clock-shaped time', () {
    expect(formatCallClock(BigInt.zero), '0:00');
    expect(formatCallClock(BigInt.from(-1000)), '0:00');
    expect(formatCallClock(BigInt.from(1000)), '0:01');
    expect(formatCallClock(BigInt.from(65000)), '1:05');
    expect(formatCallClock(BigInt.from(3661000)), '61:01');
  });
}
