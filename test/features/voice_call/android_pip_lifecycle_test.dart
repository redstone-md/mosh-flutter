import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/android_call_presentation.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import '../../support/native_call_fixture.dart';

CallViewState _call(String id,
        {bool video = false, CallViewPhase phase = CallViewPhase.active}) =>
    CallViewState(
        sessionId: 'dm',
        callId: id,
        peer: 'Alice',
        phase: phase,
        media: video ? CallMediaView.fromSnapshot(nativeCallSnapshot()) : null);

void main() {
  testWidgets('only the latest PiP window can acknowledge its video frame',
      (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(AndroidCallPresentation.channel,
        (call) async {
      calls.add(call);
      return null;
    });
    final presentation = AndroidCallPresentation();
    addTearDown(() {
      presentation.dispose();
      messenger.setMockMethodCallHandler(AndroidCallPresentation.channel, null);
    });
    presentation.update(_call('same-call', video: true));
    await tester.pump();
    calls.clear();
    await _event(tester, 'mode', 'dm/same-call', pip: true, generation: 11);
    await _event(tester, 'mode', 'dm/same-call', pip: true, generation: 12);
    await tester.pump();
    await tester.pump();
    expect(
        calls
            .where((call) => call.method == 'ready')
            .map((call) => call.arguments),
        [
          {'call': 'dm/same-call', 'generation': 12}
        ],
        reason: 'a frame from the previous Activity cannot clear a new shield');
    await _event(tester, 'mode', 'dm/same-call', pip: false, generation: 11);
    expect(presentation.inPip, isTrue,
        reason: 'a previous window cannot restore protected routes');
    await _event(tester, 'mode', 'dm/same-call', pip: false, generation: 12);
    expect(presentation.inPip, isFalse);
  });

  testWidgets(
      'only selected active video enables PiP; stale OS events cannot affect a replacement',
      (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(AndroidCallPresentation.channel,
        (call) async {
      calls.add(call);
      return null;
    });
    final presentation = AndroidCallPresentation();
    final closed = <String>[];
    presentation.onClose = (_, call) => closed.add(call);
    presentation
        .update(_call('first', video: true, phase: CallViewPhase.outgoing));
    await tester.pump();
    expect(calls.last.arguments, {'call': 'dm/first', 'video': false});
    presentation.update(_call('first', video: true));
    await tester.pump();
    expect(calls.last.arguments, {'call': 'dm/first', 'video': true});
    final count = calls.length;
    presentation.update(_call('first', video: true));
    await tester.pump();
    expect(calls.length, count);

    await _event(tester, 'mode', 'dm/first', pip: true);
    expect(presentation.inPip, true);
    await tester.pump();
    expect(calls.last.method, 'ready',
        reason: 'native chat shield waits for the video frame');
    presentation.update(_call('second'));
    await tester.pump();
    expect(calls.last.arguments, {'call': 'dm/second', 'video': false});
    await _event(tester, 'closed', 'dm/first');
    await _event(tester, 'closed', 'dm/second');
    expect(closed, ['second']);
    presentation.update(null);
    await tester.pump();
    expect(calls.last.arguments, {'call': null, 'video': false});
    await _event(tester, 'mode', null, pip: false);
    expect(presentation.inPip, false,
        reason: 'returning after call termination restores the app');
    await _event(tester, 'closed', 'dm/second');
    expect(closed, ['second']);
    presentation.dispose();
    messenger.setMockMethodCallHandler(AndroidCallPresentation.channel, null);
  });
}

Future<void> _event(WidgetTester tester, String method, String? key,
    {bool? pip, int generation = 1}) async {
  final reply = Completer<ByteData?>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      AndroidCallPresentation.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(
          method, {'call': key, 'pip': pip, 'generation': generation})),
      reply.complete);
  await reply.future;
}
