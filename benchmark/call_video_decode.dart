// What the call window pays to turn a frame's RGBA into an image. Run it
// with `flutter test`, through `scripts/call-video-bench.mjs`: flutter_tester
// is a JIT build with a software rasterizer, so this bounds the copy and
// decode work and says nothing about a GPU upload.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';

import 'support.dart';

void main() {
  test('ImageDescriptor.raw decode', () async {
    for (final size in sizes) {
      final frame = syntheticFrame(size);
      // ignore: avoid_print
      print(await measure(
          '`ImageDescriptor.raw` decode (flutter_tester, JIT, software)',
          size,
          () async => (await CallVideoRenderer.decodeRgba(frame)).dispose()));
    }
  });
}
