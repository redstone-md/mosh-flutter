// Parity tests for `call-state.dart` (lib/src/features/dm/
// call_state.dart) -- the 1-в-1 Dart port of React's
// `call-state.test.ts` (the same 5 cases). Keeps the state machine
// honest: the 4 happy-path transitions, the 4 ended transitions
// (from any phase on local_end / remote_end / decline / no_answer),
// and the no-answer timeout boundary.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/dm/call_state.dart';

void main() {
  test('idle -> outgoing on local dial', () {
    expect(nextCallPhase(CallPhase.idle, CallEvent.localDial),
        CallPhase.outgoing);
  });

  test('ringing -> active on local accept', () {
    expect(nextCallPhase(CallPhase.ringing, CallEvent.localAccept),
        CallPhase.active);
  });

  test('outgoing -> active on remote accept', () {
    expect(nextCallPhase(CallPhase.outgoing, CallEvent.remoteAccept),
        CallPhase.active);
  });

  test('any phase -> ended on local_end / remote_end / decline / no_answer',
      () {
    expect(nextCallPhase(CallPhase.outgoing, CallEvent.localEnd),
        CallPhase.ended);
    expect(nextCallPhase(CallPhase.ringing, CallEvent.localDecline),
        CallPhase.ended);
    expect(nextCallPhase(CallPhase.active, CallEvent.remoteEnd),
        CallPhase.ended);
    expect(nextCallPhase(CallPhase.outgoing, CallEvent.noAnswer),
        CallPhase.ended);
  });

  test('hasNoAnswerTimedOut fires only after the timeout from dial', () {
    const dialAt = 1000;
    // One ms before the boundary: still ringing.
    expect(
        hasNoAnswerTimedOut(dialAt, dialAt + kNoAnswerTimeoutMs - 1), false);
    // Exactly at the boundary: timed out.
    expect(hasNoAnswerTimedOut(dialAt, dialAt + kNoAnswerTimeoutMs), true);
  });
}
