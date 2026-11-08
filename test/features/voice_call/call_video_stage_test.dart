import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_frame.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_video_stage.dart';
import 'package:mosh/src/features/voice_call/call_video_surfaces.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;

import '../../support/call_video_frames.dart';
import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';

const call = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active);

void main() {
  testWidgets(
      'remote video expiry keeps preview small and fresh video recovers',
      (tester) async {
    final image = await tester
        .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(1)));
    addTearDown(image!.dispose);
    final active = CallViewState(
        sessionId: 'dm',
        callId: 'call',
        peer: 'Alice',
        phase: CallViewPhase.active,
        media: CallMediaView.fromSnapshot(nativeCallSnapshot(camera: true)));
    final renderer = CallVideoRenderer(decode: (_) async => image.clone())
      ..update(active);
    addTearDown(renderer.dispose);
    await pumpScreen(
        tester,
        Scaffold(
            body: CallView(call: active, video: renderer, onAction: (_) {})),
        settle: false);
    await renderer.receive(testCallVideoFrame(1));
    await renderer.receive(testCallVideoFrame(1, local: true));
    await tester.pump();
    await tester
        .pump(const Duration(milliseconds: CallVideoFrame.lifetimeMs - 100));
    await renderer.receive(testCallVideoFrame(2, local: true));
    await tester.pump(const Duration(milliseconds: 200));
    expect(renderer.value.remote, isNull);
    expect(renderer.value.local, isNotNull);
    final preview = find.bySemanticsLabel('Your camera preview');
    final stage = find.byType(CallVideoStage);
    expect(tester.getSize(preview).width,
        lessThan(tester.getSize(stage).width / 2),
        reason: 'a missing remote frame must not promote the local camera');
    expect(find.text('Waiting for video…'), findsOneWidget);
    await renderer.receive(testCallVideoFrame(2));
    await tester.pump();
    expect(find.text('Waiting for video…'), findsNothing);
    expect(find.bySemanticsLabel('Video from Alice'), findsOneWidget);
    renderer.update(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cleared video paints its owned image clone through the fade',
      (tester) async {
    final renderer = CallVideoRenderer()..update(call);
    addTearDown(renderer.dispose);
    await pumpScreen(tester, CallVideoStage(images: renderer, peer: 'Alice'),
        settle: false);
    await tester.runAsync(() => renderer.receive(testCallVideoFrame(1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final original = renderer.value.remote!;
    final painted =
        tester.renderObject<RenderImage>(find.byType(RawImage)).image!;
    expect(painted, isNot(same(original)));
    renderer.update(null);
    expect(original.debugDisposed, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(find.byType(RawImage), findsOneWidget);
    expect(painted.debugDisposed, isFalse);
    final bytes = await tester.runAsync(() => painted.toByteData());
    expect(bytes!.buffer.asUint8List(), testCallVideoFrame(1).pixels);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RawImage), findsNothing);
    expect(painted.debugDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'video fits a narrow call window and preserves accessible controls',
      (tester) async {
    final renderer = CallVideoRenderer()..update(call);
    addTearDown(renderer.dispose);
    tester.view.physicalSize = const Size(340, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(tester,
        Scaffold(body: CallView(call: call, video: renderer, onAction: (_) {})),
        settle: false);
    await tester.runAsync(() => renderer.receive(testCallVideoFrame(1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.bySemanticsLabel('Video from Alice'), findsOneWidget);
    expect(find.byTooltip('Hang up'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'pixel updates keep the same stage and reduced motion disables the fade',
      (tester) async {
    final images = ValueNotifier(const CallVideoImages());
    final first = await tester
        .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(1)));
    final second = await tester
        .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(2)));
    addTearDown(() {
      images.dispose();
      first!.dispose();
      second!.dispose();
    });
    await pumpScreen(
        tester,
        MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: SizedBox(
                width: 500,
                child: CallVideoStage(images: images, peer: 'Alice'))));
    images.value = CallVideoImages(remote: first);
    await tester.pump();
    final stage = tester.element(find.byType(RawImage));
    images.value = CallVideoImages(remote: second);
    await tester.pump();
    expect(tester.element(find.byType(RawImage)), same(stage));
    expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero);
    images.value = const CallVideoImages();
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stages report the device pixels that cover every lane',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = (await tester
        .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(1))))!;
    final next = (await tester
        .runAsync(() => CallVideoRenderer.decodeRgba(testCallVideoFrame(2))))!;
    final images = ValueNotifier(CallVideoImages(local: image, remote: image));
    addTearDown(() {
      images.dispose();
      image.dispose();
      next.dispose();
    });
    final reported = <CallVideoSurfaces>[];
    Future<void> show(List<double> widths) => pumpScreen(
        tester,
        CallVideoSurfaceScope(
            onSurfaces: reported.add,
            child: Column(children: [
              for (final width in widths)
                SizedBox(
                    width: width,
                    child: CallVideoStage(
                        images: images,
                        peer: 'Alice',
                        inset: false,
                        remoteCamera: true)),
            ])),
        settle: false);
    await show([640]);
    await tester.pump();
    images.value = CallVideoImages(local: next, remote: next);
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is RawImage && w.image == next),
        findsNWidgets(2));
    expect(reported, [_surfaces((312, 688), (1280, 720))],
        reason: 'new pixels in the same layout report nothing new');
    await show([640, 160]);
    await tester.pump();
    expect(reported, hasLength(1), reason: 'the larger stage still covers');
    await show([160]);
    await tester.pump();
    expect(reported.last, _surfaces((72, 148), (320, 180)));
    images.value = CallVideoImages(local: image);
    await show([160]);
    await tester.pump();
    await tester.pump();
    expect(reported, hasLength(2),
        reason: 'a waiting remote stage keeps its surfaces');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// The preview is a quarter of the stage inside its 8 px padding.
CallVideoSurfaces _surfaces((int, int) local, (int, int) remote) =>
    CallVideoSurfaces(
        local: native.Surface(width: local.$1, height: local.$2),
        remote: native.Surface(width: remote.$1, height: remote.$2));
