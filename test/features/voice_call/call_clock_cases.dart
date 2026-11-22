// The active call's elapsed-time label: clock-shaped m:ss from the call's
// start.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/voice_call/call_clock.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('an active call shows the time since it started', (tester) async {
    await pumpScreen(
        tester,
        Scaffold(
            body: CallView(
                call: const CallViewState(
                    sessionId: 'dm',
                    callId: 'call',
                    peer: 'Alice',
                    phase: CallViewPhase.active,
                    startedAtMs: 1000,
                    audioReady: true),
                now: () => 66000,
                onAction: (_) {})),
        settle: false);

    expect(find.text('1:05'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('formatCallClock renders clock-shaped time', () {
    expect(formatCallClock(BigInt.zero), '0:00');
    expect(formatCallClock(BigInt.from(-1000)), '0:00');
    expect(formatCallClock(BigInt.from(1000)), '0:01');
    expect(formatCallClock(BigInt.from(65000)), '1:05');
    expect(formatCallClock(BigInt.from(3661000)), '61:01');
  });
}
