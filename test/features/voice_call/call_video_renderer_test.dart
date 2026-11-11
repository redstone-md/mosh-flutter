import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_video_frame.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';

import '../../support/call_video_frames.dart';
import '../../support/native_call_fixture.dart';

const call = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active);
final withCameras = cameras(local: true, remote: true);

CallViewState cameras(
        {required bool local, required bool remote}) =>
    CallViewState(
        sessionId: 'dm',
        callId: 'call',
        peer: 'Alice',
        phase: CallViewPhase.active,
        media: CallMediaView.fromSnapshot(
            nativeCallSnapshot(camera: local, remoteCamera: remote)));

/// A renderer whose decoder answers at once, so the fake clock alone ages frames.
Future<CallVideoRenderer> clonedRenderer(
    WidgetTester tester, CallViewState state) async {
  final source = (await tester
      .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(1))))!;
  addTearDown(source.dispose);
  final renderer = CallVideoRenderer(decode: (_) async => source.clone())
    ..update(state);
  addTearDown(renderer.dispose);
  return renderer;
}

void main() {
  testWidgets('a slow decoder cannot publish an expired frame in the same call',
      (tester) async {
    final pending = Completer<ui.Image>();
    final renderer = CallVideoRenderer(decode: (_) => pending.future)
      ..update(call);
    addTearDown(renderer.dispose);
    final receiving = renderer.receive(
        testCallVideoFrame(1, sourceAgeMs: CallVideoFrame.lifetimeMs - 1000));
    await tester.runAsync(() async {
      final image = await CallVideoRenderer.decodeRgba(testCallVideoFrame(1));
      await Future<void>.delayed(const Duration(milliseconds: 1050));
      pending.complete(image);
    });
    expect(await receiving, isFalse);
    expect(renderer.value.remote, isNull);
  });
  testWidgets('renders actual RGBA', (tester) async {
    final renderer = CallVideoRenderer()..update(call);
    addTearDown(renderer.dispose);
    await tester.runAsync(() async {
      expect(await renderer.receive(testCallVideoFrame(1)), isTrue);
      final bytes = await (renderer.value.remote! as DecodedVideo)
          .image
          .toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes!.buffer.asUint8List(), testCallVideoFrame(1).pixels);
    });
    expect(await renderer.receive(testCallVideoFrame(1)), isFalse);
  });

  testWidgets('a paused stream freezes both frames until the long limit',
      (tester) async {
    final renderer = await clonedRenderer(tester, withCameras);
    expect(await renderer.receive(testCallVideoFrame(1)), isTrue);
    expect(await renderer.receive(testCallVideoFrame(1, local: true)), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(renderer.value.remote, isNotNull);
    expect(renderer.value.local, isNotNull);
    await tester.pump(const Duration(seconds: 3));
    expect(renderer.value.remote, isNull);
    expect(renderer.value.local, isNull);
  });

  testWidgets('a camera turned off clears its frame at once', (tester) async {
    final renderer = await clonedRenderer(tester, withCameras);
    expect(await renderer.receive(testCallVideoFrame(1)), isTrue);
    expect(await renderer.receive(testCallVideoFrame(1, local: true)), isTrue);
    renderer.update(cameras(local: true, remote: false));
    expect(renderer.value.remote, isNull);
    expect(renderer.value.local, isNotNull);
    renderer.update(cameras(local: false, remote: false));
    expect(renderer.value.local, isNull);
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
