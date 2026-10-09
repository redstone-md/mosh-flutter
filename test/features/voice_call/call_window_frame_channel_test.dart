import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_window_frame_channel.dart';
import 'package:mosh/src/features/voice_call/call_window_frame_receiver.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';

import '../../support/call_video_frames.dart';

void main() {
  testWidgets('receiver decodes pixels and acknowledges the exact call frame',
      (tester) async {
    await tester.runAsync(() async {
      final channel = await CallWindowFrameChannel.bind();
      final renderer = CallVideoRenderer()
        ..update(const CallViewState(
            sessionId: 'dm',
            callId: 'call',
            peer: 'Alice',
            phase: CallViewPhase.active));
      final acknowledged = Completer<Map<String, Object?>>();
      final receiver = CallWindowFrameReceiver(renderer, (ack) async {
        acknowledged.complete(ack);
      });
      try {
        await receiver.connect(
            channel.descriptor['port'] as int, channel.token);
        await channel.ready;
        expect(channel.send(testCallVideoFrame(17).encode()), isTrue);
        final ack =
            await acknowledged.future.timeout(const Duration(seconds: 2));
        expect(ack, {
          'sessionId': 'dm',
          'callId': 'call',
          'sequence': 17,
          'local': false
        });
        final pixels = await renderer.value.remote!
            .toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(pixels!.buffer.asUint8List(), testCallVideoFrame(17).pixels);
        await receiver.dispose();
        expect(renderer.value.remote, isNull);
        await expectLater(
            receiver.connect(channel.descriptor['port'] as int, channel.token),
            throwsStateError);
      } finally {
        await receiver.dispose();
        await channel.dispose();
        renderer.dispose();
      }
    });
  });
  test('a connecting renderer cannot acquire a second stream', () async {
    final channel = await CallWindowFrameChannel.bind();
    addTearDown(channel.dispose);
    final renderer = CallVideoRenderer();
    final receiver = CallWindowFrameReceiver(renderer, (_) async {});
    addTearDown(() async {
      await receiver.dispose();
      renderer.dispose();
    });
    final port = channel.descriptor['port'] as int;
    final connecting = receiver.connect(port, channel.token);
    await expectLater(receiver.connect(port, channel.token), throwsStateError);
    await connecting;
    await channel.ready.timeout(const Duration(seconds: 2));
  });
  test('only the one-time renderer capability admits presentation bytes',
      () async {
    final channel = await CallWindowFrameChannel.bind();
    addTearDown(channel.dispose);
    final port = channel.descriptor['port'] as int;
    final wrong = await CallWindowFrameChannel.connect(port, '0' * 64);
    await wrong.drain<void>().timeout(const Duration(seconds: 2));
    wrong.destroy();
    final renderer = await CallWindowFrameChannel.connect(port, channel.token);
    final data = renderer.first;
    await channel.ready.timeout(const Duration(seconds: 2));
    expect(channel.send([1, 2, 3]), isTrue);
    expect(await data.timeout(const Duration(seconds: 2)), [1, 2, 3]);
    renderer.destroy();
    final reused = await CallWindowFrameChannel.connect(port, channel.token);
    await reused.drain<void>().timeout(const Duration(seconds: 2));
    reused.destroy();
    await channel.dispose();
    expect(channel.send([4]), isFalse);
  });

  test('renderer reset during pixel write closes only presentation', () async {
    final channel = await CallWindowFrameChannel.bind();
    addTearDown(channel.dispose);
    final renderer = await CallWindowFrameChannel.connect(
        channel.descriptor['port'] as int, channel.token);
    final subscription = renderer.listen((_) {});
    subscription.pause();
    final closed = Completer<void>();
    channel.onClosed = () => closed.complete();
    await channel.ready.timeout(const Duration(seconds: 2));
    expect(channel.send(Uint8List(1280 * 720 * 4)), true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    renderer.destroy();
    await closed.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
    expect(channel.send([0]), false);
  });

  test('invalid capability is rejected before connecting', () async {
    await expectLater(
        CallWindowFrameChannel.connect(0, 'a' * 64), throwsFormatException);
    await expectLater(
        CallWindowFrameChannel.connect(1234, 'a' * 65), throwsFormatException);
    await expectLater(
        CallWindowFrameChannel.connect(1234, 'secret'), throwsFormatException);
  });
}
