import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_frame.dart';
import 'package:mosh/src/features/voice_call/call_window_input.dart';

import '../../support/call_video_frames.dart';

void main() {
  test('binary frames and Russian control text survive every byte boundary',
      () async {
    final frames = <CallVideoFrame>[];
    final control = 'mosh-call-window:{"name":"Алиса"}';
    final packet = [
      ...utf8.encode('$control\n'),
      ...testCallVideoFrame(1).encode(),
      ...testCallVideoFrame(2).encode(),
      ...utf8.encode('$control\n')
    ];
    final input = CallWindowInput(
        Stream.fromIterable(packet.map((b) => [b])), frames.add);
    final lines = await input.lines.toList();
    expect(lines, [control, control]);
    expect(frames.map((f) => f.sequence), [1, 2]);
    expect(frames.first.pixels, testCallVideoFrame(1).pixels);
    await input.dispose();
  });

  test('oversized frame header is refused before allocating the body',
      () async {
    final bytes = Uint8List(12)..setRange(0, 4, CallVideoFrame.magic);
    ByteData.sublistView(bytes)
      ..setUint32(4, 100)
      ..setUint32(8, CallVideoFrame.maximumBytes + 1);
    final input =
        CallWindowInput(Stream.value(bytes), (_) => fail('invalid frame'));
    await expectLater(input.lines.toList(), throwsFormatException);
    await input.dispose();
  });

  test('partial frame on pipe closure is an error rather than a stale image',
      () async {
    final bytes = testCallVideoFrame(1).encode();
    final input = CallWindowInput(
        Stream.value(bytes.sublist(0, bytes.length - 1)),
        (_) => fail('partial frame'));
    await expectLater(input.lines.toList(), throwsFormatException);
    await input.dispose();
  });
}
