import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';
import 'package:mosh/src/features/voice_call/call_video_stage.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';

import '../../support/call_video_frames.dart';
import '../../support/pump.dart';

const call = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active);

void main() {
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
}
