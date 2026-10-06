import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_pipe.dart';

void main() {
  test('asynchronous output failure closes pending requests', () async {
    final input = StreamController<String>();
    final output = Completer<void>();
    final pipe =
        CallWindowPipe(input.stream, (_) {}, outputDone: output.future);
    var closed = 0;
    pipe.onClosed = () => closed++;
    final failed = expectLater(pipe.invoke('call-show'), throwsStateError);
    output.completeError(StateError('broken pipe'));
    await failed;
    expect(closed, 1);
    await pipe.dispose();
    await input.close();
  });

  test('a closed output fails requests without unhandled dispatch errors',
      () async {
    final input = StreamController<String>();
    final pipe =
        CallWindowPipe(input.stream, (_) => throw StateError('closed'));
    await expectLater(pipe.invoke('call-show'), throwsStateError);
    await pipe.dispose();
    await input.close();
  });

  test('a missing command handler returns an error to the caller', () async {
    final toParent = StreamController<String>();
    final toChild = StreamController<String>();
    final parent = CallWindowPipe(toParent.stream, toChild.add);
    final child = CallWindowPipe(toChild.stream, toParent.add);
    await expectLater(parent.invoke('unknown'), throwsStateError);
    await parent.dispose();
    await child.dispose();
    await toParent.close();
    await toChild.close();
  });

  test(
      'stdio carries display metadata and call-bound commands in both directions',
      () async {
    final toParent = StreamController<String>();
    final toChild = StreamController<String>();
    final parent = CallWindowPipe(toParent.stream, toChild.add);
    final child = CallWindowPipe(toChild.stream, toParent.add);
    const state = CallViewState(
        sessionId: 'origin',
        callId: 'call',
        peer: 'Alice',
        phase: CallViewPhase.active,
        audioReady: true);
    CallViewState? shown;
    CallViewCommand? received;
    child.onMethod = (call) async {
      shown = CallViewState.fromMap(call.arguments as Map<Object?, Object?>);
      return null;
    };
    parent.onMethod = (call) async {
      received =
          CallViewCommand.fromMap(call.arguments as Map<Object?, Object?>);
      return 'ack';
    };
    toChild.add('The Dart VM service is listening on a debug port');
    await parent.invoke('call-present', state.toMap());
    expect(shown!.toMap(), state.toMap());
    expect(
        await child.invoke(
            'call-command', state.command(CallViewAction.end).toMap()),
        'ack');
    expect(received!.sessionId, 'origin');
    expect(received!.callId, 'call');
    expect(received!.action, CallViewAction.end);
    await parent.dispose();
    await child.dispose();
    await toParent.close();
    await toChild.close();
  });

  test('request errors are bounded and disconnect fails pending work',
      () async {
    final input = StreamController<String>();
    final requests = <String>[];
    final pipe = CallWindowPipe(input.stream, requests.add);
    final pending = pipe.invoke('call-show');
    final failed = expectLater(pending, throwsStateError);
    await input.close();
    await failed;
    expect(requests, hasLength(1));
    await expectLater(pipe.invoke('call-show'), throwsStateError);
    await pipe.dispose();
  });

  test('malformed protocol data closes the pipe without parsing runtime logs',
      () async {
    final input = StreamController<String>();
    final pipe = CallWindowPipe(input.stream, (_) {});
    var closed = 0;
    pipe.onClosed = () => closed++;
    input.add('${CallWindowPipe.prefix}invalid');
    await Future<void>.delayed(Duration.zero);
    expect(closed, 1);
    await expectLater(pipe.invoke('call-show'), throwsStateError);
    await pipe.dispose();
    expect(closed, 1);
    await input.close();
  });
}
