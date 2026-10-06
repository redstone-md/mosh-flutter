import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_control_gate.dart';

void main() {
  test('duplicates cannot release a call while another call completes',
      () async {
    final gate = CallControlGate();
    final first = Completer<void>();
    final second = Completer<void>();
    final runningFirst = gate.run('first', () => first.future);
    var duplicateRan = false;
    await gate.run('first', () async => duplicateRan = true);
    final runningSecond = gate.run('second', () => second.future);
    final waitingSecond = gate.wait('second');
    second.complete();
    await Future.wait([runningSecond, waitingSecond]);
    expect(duplicateRan, isFalse);
    expect(gate.isBusy('first'), isTrue);
    expect(gate.isBusy('second'), isFalse);
    first.complete();
    await runningFirst;
    expect(gate.isBusy('first'), isFalse);
  });

  test('waiting for a failed operation observes settlement without rethrowing',
      () async {
    final gate = CallControlGate();
    final result = Completer<void>();
    final running = gate.run('call', () => result.future);
    final assertion = expectLater(running, throwsStateError);
    final waiting = gate.wait('call');
    result.completeError(StateError('rejected'));
    await Future.wait([assertion, waiting]);
    expect(gate.isBusy('call'), isFalse);
    await gate.wait('absent');
  });
}
