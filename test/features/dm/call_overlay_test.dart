// Parity tests for `CallOverlay` (lib/src/features/dm/call_overlay.dart)
// -- the 1-в-1 port of React's `CallOverlay.tsx`. Asserts the mute/hang-up
// buttons fire, the mute icon + tint swap when muted, the duration timer
// renders m:ss from `startedAtMs`, and Esc fires onHangUp.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/call_overlay.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import '../../support/pump.dart';

ActiveCall _active({required int startedAtMs}) => ActiveCall(
      callId: 'call-1',
      direction: 'caller',
      keyB64: 'k',
      noncePrefixB64: 'n',
      startedAtMs: BigInt.from(startedAtMs),
    );

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required CallOverlay overlay,
}) =>
    pumpScreen(tester, Scaffold(body: overlay));

void main() {
  testWidgets(
    'mute button fires onToggleMute + shows the mic icon when not muted',
    (tester) async {
      var muteCount = 0;
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          muted: false,
          onToggleMute: () => muteCount++,
          onHangUp: () {},
          l: await _l(),
        ),
      );
      expect(find.byIcon(Icons.mic), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic));
      expect(muteCount, 1);
    },
  );

  testWidgets(
    'hang-up button fires onHangUp',
    (tester) async {
      var hangUpCount = 0;
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          muted: false,
          onToggleMute: () {},
          onHangUp: () => hangUpCount++,
          l: await _l(),
        ),
      );
      await tester.tap(find.byIcon(Icons.phone_disabled));
      expect(hangUpCount, 1);
    },
  );

  testWidgets(
    'Esc fires onHangUp',
    (tester) async {
      var hangUpCount = 0;
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          muted: false,
          onToggleMute: () {},
          onHangUp: () => hangUpCount++,
          l: await _l(),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(hangUpCount, 1);
    },
  );

  testWidgets(
    'renders the peer label + a 0:00 timer at the start',
    (tester) async {
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          muted: false,
          onToggleMute: () {},
          onHangUp: () {},
          now: () => 0,
          l: await _l(),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
    },
  );

  testWidgets(
    'renders 1:05 for a 65-second elapsed call',
    (tester) async {
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          muted: false,
          onToggleMute: () {},
          onHangUp: () {},
          now: () => 65000,
          l: await _l(),
        ),
      );
      expect(find.text('1:05'), findsOneWidget);
    },
  );

  testWidgets(
    'muted state swaps the icon to mic_off',
    (tester) async {
      await _pump(
        tester,
        overlay: CallOverlay(
          active: _active(startedAtMs: 0),
          peerLabel: 'Alice',
          muted: true,
          onToggleMute: () {},
          onHangUp: () {},
          l: await _l(),
        ),
      );
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
    },
  );

  test('formatCallClock mirrors React formatClock', () {
    expect(formatCallClock(BigInt.zero), '0:00');
    expect(formatCallClock(BigInt.from(-1000)), '0:00');
    expect(formatCallClock(BigInt.from(1000)), '0:01');
    expect(formatCallClock(BigInt.from(65000)), '1:05');
    expect(formatCallClock(BigInt.from(3661000)), '61:01');
  });
}
