import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';

import '../../support/call_video_frames.dart';

const call = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active);

void main() {
  testWidgets('a slow decoder cannot publish an expired frame in the same call',
      (tester) async {
    final pending = Completer<ui.Image>();
    final renderer = CallVideoRenderer(decode: (_) => pending.future)
      ..update(call);
    addTearDown(renderer.dispose);
    final receiving = renderer.receive(testCallVideoFrame(1));
    await tester.runAsync(() async {
      final image = await CallVideoRenderer.decodeRgba(testCallVideoFrame(1));
      await Future<void>.delayed(const Duration(milliseconds: 1050));
      pending.complete(image);
    });
    expect(await receiving, isFalse);
    expect(renderer.value.remote, isNull);
  });
  testWidgets('renders actual RGBA and clears stale imagery after one second',
      (tester) async {
    final renderer = CallVideoRenderer()..update(call);
    addTearDown(renderer.dispose);
    await tester.runAsync(() async {
      expect(await renderer.receive(testCallVideoFrame(1)), isTrue);
      final bytes = await renderer.value.remote!
          .toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes!.buffer.asUint8List(), testCallVideoFrame(1).pixels);
    });
    expect(renderer.value.remote, isNotNull);
    expect(await renderer.receive(testCallVideoFrame(1)), isFalse);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1050)));
    await tester.pump();
    expect(renderer.value.remote, isNull);
  });

  testWidgets('a late decoder result cannot paint a replacement call',
      (tester) async {
    final pending = Completer<ui.Image>();
    final renderer = CallVideoRenderer(decode: (_) => pending.future)
      ..update(call);
    addTearDown(renderer.dispose);
    final receiving = renderer.receive(testCallVideoFrame(1));
    expect(await renderer.receive(testCallVideoFrame(2)), isFalse,
        reason: 'one decode in flight');
    renderer.update(const CallViewState(
        sessionId: 'dm',
        callId: 'replacement',
        peer: 'Bob',
        phase: CallViewPhase.active));
    final image = await tester
        .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(1)));
    pending.complete(image!);
    expect(await receiving, isFalse);
    expect(renderer.value.remote, isNull);
  });

  testWidgets('unconfirmed calls do not render remote video', (tester) async {
    final renderer = CallVideoRenderer()
      ..update(const CallViewState(
          sessionId: 'dm',
          callId: 'call',
          peer: 'Alice',
          phase: CallViewPhase.confirming));
    addTearDown(renderer.dispose);
    expect(await renderer.receive(testCallVideoFrame(1)), isFalse);
  });
}
