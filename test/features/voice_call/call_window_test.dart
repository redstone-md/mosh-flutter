import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_video_stage.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_parts.dart';

import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';

const _remote = CallVideoPicture(8, 1280, 720);
const _preview = CallVideoPicture(7, 320, 180);

CallViewState _call(
        {CallViewPhase phase = CallViewPhase.active,
        bool muted = false,
        bool camera = false,
        bool cameraFailed = false,
        bool remoteCamera = true}) =>
    CallViewState(
        sessionId: 'dm',
        callId: 'call',
        peer: 'Alice',
        phase: phase,
        muted: muted,
        audioReady: true,
        media: CallMediaView.fromSnapshot(nativeCallSnapshot(
            microphone: true,
            camera: camera,
            cameraFailed: cameraFailed,
            remoteCamera: remoteCamera)));

/// The open call in a window of [size], over [pictures].
Future<List<CallViewAction>> _open(WidgetTester tester, CallViewState call,
    {Size size = const Size(720, 460),
    CallVideoPictures pictures = const CallVideoPictures()}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  final video = ValueNotifier(pictures);
  addTearDown(video.dispose);
  final actions = <CallViewAction>[];
  await pumpScreen(
      tester,
      Scaffold(
          body: CallView(
              call: call,
              video: video,
              onAction: actions.add,
              onDeviceSelected: (_) {})),
      settle: false);
  await tester.pump(const Duration(milliseconds: 150));
  return actions;
}

const _video = CallVideoPictures(remote: _remote, local: _preview);
final _controls = find.byTooltip('Hang up').hitTestable();

/// A mouse resting in the middle of the window, clear of the dock.
Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(find.byType(CallView)));
  addTearDown(mouse.removePointer);
  return mouse;
}

/// Lets the call rest for [time], then the controls' fade end.
Future<void> _rest(WidgetTester tester,
    [Duration time = const Duration(seconds: 3)]) async {
  await tester.pump(time);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('an incoming call offers only Decline and Accept',
      (tester) async {
    await _open(tester, _call(phase: CallViewPhase.incoming));
    expect(find.byTooltip('Decline call'), findsOneWidget);
    expect(find.byTooltip('Accept call'), findsOneWidget);
    for (final other in ['Mute', 'Turn camera on', 'Call devices']) {
      expect(find.byTooltip(other), findsNothing, reason: other);
    }
  });

  testWidgets(
      'the controls leave the other side\'s video after three seconds of '
      'rest and a pointer move, a touch or a key brings them back',
      (tester) async {
    final actions = await _open(tester, _call(), pictures: _video);
    final mouse = await _mouse(tester);
    await _rest(tester, const Duration(seconds: 2));
    expect(_controls, findsOneWidget, reason: 'two seconds is not a rest');
    await _rest(tester, const Duration(seconds: 1));
    expect(_controls, findsNothing);
    expect(find.bySemanticsLabel('Your camera preview'), findsOneWidget,
        reason: 'your own camera stays');

    await mouse.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(_controls, findsOneWidget, reason: 'pointer move');

    await _rest(tester);
    expect(_controls, findsNothing);
    await tester.tapAt(tester.getCenter(find.byTooltip('Hang up')));
    await tester.pump();
    expect(_controls, findsOneWidget, reason: 'touch');
    expect(actions, isEmpty,
        reason: 'the touch that brings the buttons back presses none');

    await _rest(tester);
    expect(_controls, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(_controls, findsOneWidget, reason: 'key');
  });

  testWidgets('a muted microphone keeps its mark when the controls are gone',
      (tester) async {
    await _open(tester, _call(muted: true), pictures: _video);
    double mark() => tester
        .widget<AnimatedOpacity>(find.ancestor(
            of: find.byType(CallMutedMark),
            matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(mark(), 0, reason: 'the muted button says it while it is shown');
    await _rest(tester);
    expect(_controls, findsNothing);
    expect(mark(), 1);
  });

  testWidgets('the controls stay without the other side\'s video',
      (tester) async {
    for (final (reason, call, pictures) in [
      ('voice', _call(remoteCamera: false), const CallVideoPictures()),
      ('waiting for video', _call(), const CallVideoPictures()),
      (
        'camera preview',
        _call(camera: true, remoteCamera: false),
        const CallVideoPictures(local: _preview)
      ),
      ('a warning is shown', _call(cameraFailed: true), _video),
    ]) {
      await _open(tester, call, pictures: pictures);
      await _rest(tester, const Duration(seconds: 10));
      expect(_controls, findsOneWidget, reason: reason);
    }
  });

  testWidgets('the controls stay while the pointer is over the dock',
      (tester) async {
    await _open(tester, _call(), pictures: _video);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Mute')));
    await _rest(tester, const Duration(seconds: 10));
    expect(_controls, findsOneWidget);

    await mouse.moveTo(tester.getCenter(find.byType(CallView)));
    await _rest(tester);
    expect(_controls, findsNothing, reason: 'the rest starts off the dock');
  });

  testWidgets(
      'the controls stay while the keyboard\'s focus is on a button, until '
      'the pointer takes over', (tester) async {
    await _open(tester, _call(), pictures: _video);
    final mouse = await _mouse(tester);
    await _rest(tester);
    expect(_controls, findsNothing);

    // The first key brings the buttons back, the next one reaches them.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _rest(tester, const Duration(seconds: 10));
    expect(_controls, findsOneWidget);

    await mouse.moveBy(const Offset(10, 0));
    await _rest(tester);
    expect(_controls, findsNothing,
        reason: 'the focus left on a button does not hold them for good');
  });

  testWidgets('the video takes all the window gives it without being cut',
      (tester) async {
    const upright = CallVideoPicture(8, 720, 1280);
    for (final (window, remote, stage) in const [
      (Size(390, 640), _remote, Size(390, 219.375)),
      // A phone on its side: the picture has the whole height of the screen.
      (Size(844, 390), _remote, Size(390 * 16 / 9, 390)),
      // Two phones held upright: the stage takes the shape of the frame.
      (Size(390, 844), upright, Size(390, 390 * 16 / 9)),
      (Size(844, 390), upright, Size(390 * 9 / 16, 390)),
    ]) {
      await _open(tester, _call(),
          size: window,
          pictures: CallVideoPictures(remote: remote, local: _preview));
      final shown = tester.getSize(find.byType(CallVideoStage));
      final reason = '$window, ${remote.width}x${remote.height}';
      expect(shown.width, closeTo(stage.width, 0.01), reason: reason);
      expect(shown.height, closeTo(stage.height, 0.01), reason: reason);
      expect(tester.takeException(), isNull, reason: reason);
    }
  });
}
