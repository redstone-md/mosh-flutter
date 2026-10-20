import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/mobile_call_frame.dart';
import '../../support/pump.dart';

void main() {
  for (final ratio in [1.0, 3.0]) {
    testWidgets('floating video follows every pointer move at DPR $ratio',
        (tester) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(400 * ratio, 800 * ratio);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const video = Key('floating-video');
      await pumpScreen(
          tester,
          const Scaffold(
              body: MobileCallFrame(
                  expanded: false,
                  video: true,
                  child: ColoredBox(key: video, color: Colors.black))));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(video)));
      // Establish the drag, then deliver faster input than rendering.
      await gesture.moveBy(const Offset(-24, 24));
      await tester.pump();
      final before = tester.getTopLeft(find.byKey(video));
      for (var move = 0; move < 10; move++) {
        await gesture.moveBy(const Offset(-8, 12));
      }
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(video)) - before,
          const Offset(-80, 120));
      for (var move = 0; move < 4; move++) {
        await gesture.moveBy(const Offset(8, -12));
        await tester.pump();
      }
      expect(
          tester.getTopLeft(find.byKey(video)) - before, const Offset(-48, 72));
      await gesture.up();
    });
  }
}
