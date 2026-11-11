import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_video_stage.dart';
import 'package:mosh/src/features/voice_call/call_video_surfaces.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;

import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';

const call = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active);

const _preview = TextureVideo(7, 320, 180);
const _remote = TextureVideo(8, 1280, 720);

void main() {
  testWidgets(
      'a missing remote frame keeps the preview small until video returns',
      (tester) async {
    final active = CallViewState(
        sessionId: 'dm',
        callId: 'call',
        peer: 'Alice',
        phase: CallViewPhase.active,
        media: CallMediaView.fromSnapshot(nativeCallSnapshot(camera: true)));
    final images = ValueNotifier(const CallVideoImages(local: _preview));
    addTearDown(images.dispose);
    await pumpScreen(tester,
        Scaffold(body: CallView(call: active, video: images, onAction: (_) {})),
        settle: false);
    await tester.pump(const Duration(milliseconds: 150));
    final preview = find.bySemanticsLabel('Your camera preview');
    final stage = find.byType(CallVideoStage);
    expect(tester.getSize(preview).width,
        lessThan(tester.getSize(stage).width / 2),
        reason: 'a missing remote frame must not promote the local camera');
    expect(find.text('Waiting for video…'), findsOneWidget);
    images.value = const CallVideoImages(local: _preview, remote: _remote);
    await tester.pump();
    expect(find.text('Waiting for video…'), findsNothing);
    expect(find.bySemanticsLabel('Video from Alice'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('video fits a narrow window and preserves accessible controls',
      (tester) async {
    final images = ValueNotifier(const CallVideoImages(remote: _remote));
    addTearDown(images.dispose);
    tester.view.physicalSize = const Size(340, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(tester,
        Scaffold(body: CallView(call: call, video: images, onAction: (_) {})),
        settle: false);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(Texture), findsOneWidget);
    expect(find.bySemanticsLabel('Video from Alice'), findsOneWidget);
    expect(find.byTooltip('Hang up'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a new frame size keeps the same stage and reduced motion disables '
      'the fade', (tester) async {
    final images = ValueNotifier(const CallVideoImages());
    addTearDown(images.dispose);
    await pumpScreen(
        tester,
        MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: SizedBox(
                width: 500,
                child: CallVideoStage(images: images, peer: 'Alice'))));
    images.value = const CallVideoImages(remote: _remote);
    await tester.pump();
    final stage = tester.element(find.byType(Texture));
    images.value = const CallVideoImages(remote: TextureVideo(8, 640, 360));
    await tester.pump();
    expect(tester.element(find.byType(Texture)), same(stage));
    expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero);
    images.value = const CallVideoImages();
    await tester.pump();
    expect(find.byType(Texture), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stages report the device pixels that cover every lane',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images =
        ValueNotifier(const CallVideoImages(local: _preview, remote: _remote));
    addTearDown(images.dispose);
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
    images.value = const CallVideoImages(
        local: _preview, remote: TextureVideo(8, 640, 360));
    await tester.pump();
    expect(reported, [_surfaces((312, 688), (1280, 720))],
        reason: 'a new frame size in the same layout reports nothing new');
    await show([640, 160]);
    await tester.pump();
    expect(reported, hasLength(1), reason: 'the larger stage still covers');
    await show([160]);
    await tester.pump();
    expect(reported.last, _surfaces((72, 148), (320, 180)));
    images.value = const CallVideoImages(local: _preview);
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
