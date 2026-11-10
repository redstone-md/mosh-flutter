import 'dart:convert';
import 'dart:typed_data';

import 'package:mosh/src/features/voice_call/call_video_frame.dart';

/// The frame sizes and sampling every call video benchmark shares; the Rust
/// half in `mosh-core/src/native_call/benchmark.rs` uses the same.
const sizes = [(640, 360), (1280, 720), (1920, 1080)];
const warmUps = 5;
const runs = 60;

/// A remote frame of [size] whose bytes vary across the picture.
CallVideoFrame syntheticFrame((int, int) size, {int sequence = 1}) {
  final (width, height) = size;
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; ++i) {
    pixels[i] = (i * 31) >> 3;
  }
  return CallVideoFrame(
      sessionId: 'dm',
      callId: 'call',
      sequence: sequence,
      width: width,
      height: height,
      local: false,
      pixels: pixels);
}

/// One row for `scripts/call-video-bench.mjs`: the median of `runs` timed
/// calls of [run] after `warmUps` untimed ones.
Future<String> measure(
    String name, (int, int) size, Future<void> Function() run) async {
  final micros = <int>[];
  for (var i = 0; i < warmUps + runs; ++i) {
    final elapsed = Stopwatch()..start();
    await run();
    if (i >= warmUps) micros.add(elapsed.elapsedMicroseconds);
  }
  micros.sort();
  return 'call-video-bench ${jsonEncode({
        'case': name,
        'width': size.$1,
        'height': size.$2,
        'ms': micros[runs ~/ 2] / 1000
      })}';
}
