import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';
import '../../support/call_video_frames.dart';
import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'receive-only call exposes camera and microphone recovery at minimum width',
      (tester) async {
    tester.view.physicalSize = const Size(340, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final actions = <CallViewAction>[];
    final call = _call();
    await pumpScreen(
        tester,
        Scaffold(
            body: CallView(
                call: call, onAction: actions.add, onDeviceSelected: (_) {})),
        settle: false);
    expect(find.text('Microphone unavailable. You can still listen.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Turn camera on'));
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Hang up'));
    expect(actions,
        [CallViewAction.camera, CallViewAction.mute, CallViewAction.end]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'device selection returns a call-bound command through shared selector',
      (tester) async {
    CallViewCommand? command;
    await pumpScreen(
        tester,
        Scaffold(
            body: CallView(
                call: _call(),
                onAction: (_) {},
                onDeviceSelected: (next) => command = next)),
        settle: false);
    await tester.tap(find.byTooltip('Call devices'));
    await tester.pumpAndSettle();
    expect(find.byType(MoshSelect<String?>), findsNWidgets(3));
    final input = tester
        .widget<MoshSelect<String?>>(find.byType(MoshSelect<String?>).first);
    input.onChanged!('mic');
    await tester.pumpAndSettle();
    expect(command!.sessionId, 'dm');
    expect(command!.callId, 'call');
    expect(command!.action, CallViewAction.selectInput);
    expect(command!.deviceId, 'mic');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('native video and receive-only notice fit the minimum window',
      (tester) async {
    tester.view.physicalSize = const Size(340, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = await tester
        .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(1)));
    final images = ValueNotifier(CallVideoImages(remote: image, local: image));
    addTearDown(() {
      images.dispose();
      image!.dispose();
    });
    for (final phase in [CallViewPhase.active, CallViewPhase.incoming]) {
      final call = CallViewState(
          sessionId: 'dm',
          callId: 'call',
          peer: 'Alice',
          phase: phase,
          media: CallMediaView.fromSnapshot(nativeCallSnapshot(camera: true)));
      await pumpScreen(
          tester,
          Scaffold(
              body: CallView(
                  call: call,
                  video: images,
                  onAction: (_) {},
                  onDeviceSelected: (_) {})),
          settle: false);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      expect(
          find.byTooltip(
              phase == CallViewPhase.active ? 'Hang up' : 'Decline call'),
          findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('child metadata preserves real flags and contains no media credentials',
      () {
    final original = _call();
    final copy = CallViewState.fromMap(original.toMap());
    expect(copy.media!.microphoneAvailable, false);
    expect(copy.media!.cameraRequested, false);
    expect(copy.toMap().keys, isNot(contains('keyB64')));
    expect(
        copy
            .command(CallViewAction.selectCamera, deviceId: 'camera')
            .toMap()['deviceId'],
        'camera');
  });
}

CallViewState _call() => CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active,
    audioReady: true,
    media: CallMediaView.fromSnapshot(nativeCallSnapshot()));
