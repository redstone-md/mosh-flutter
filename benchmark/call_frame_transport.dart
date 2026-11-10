// What a frame costs between the main process and the call window: the
// repository's own encode, loopback channel and parser, with one
// acknowledgement per frame like production. Run it compiled, through
// `scripts/call-video-bench.mjs`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mosh/src/features/voice_call/call_video_frame.dart';
import 'package:mosh/src/features/voice_call/call_window_frame_channel.dart';
import 'package:mosh/src/features/voice_call/call_window_input.dart';

import 'support.dart';

Future<void> main(List<String> arguments) => arguments.isEmpty
    ? _sender()
    : _receiver(int.parse(arguments[0]), arguments[1]);

/// The call window's side: parses each frame and acknowledges its sequence.
Future<void> _receiver(int port, String token) async {
  final socket = await CallWindowFrameChannel.connect(port, token);
  final input =
      CallWindowInput(socket, (frame) => stdout.writeln(frame.sequence));
  await input.lines.drain<void>();
  exit(0);
}

Future<void> _sender() async {
  final channel = await CallWindowFrameChannel.bind();
  final script = Platform.script.toFilePath();
  final receiver = await Process.start(Platform.resolvedExecutable, [
    ...Platform.executableArguments,
    if (script.endsWith('.dart')) script,
    '${channel.descriptor['port']}',
    channel.token,
  ]);
  unawaited(stderr.addStream(receiver.stderr));
  final acknowledged = StreamIterator(
      receiver.stdout.transform(utf8.decoder).transform(const LineSplitter()));
  // A receiver that dies before connecting must not leave the sender waiting.
  await Future.any([
    channel.ready,
    receiver.exitCode.then<void>(
        (code) => throw StateError('The receiver exited with $code')),
  ]);
  var sequence = 0;
  for (final size in sizes) {
    final pixels = syntheticFrame(size).pixels;
    stdout.writeln(await measure(
        'call window socket: encode, send, parse, acknowledge', size, () async {
      final frame = CallVideoFrame(
          sessionId: 'dm',
          callId: 'call',
          sequence: ++sequence,
          width: size.$1,
          height: size.$2,
          local: false,
          pixels: pixels);
      if (!channel.send(frame.encode()) ||
          !await acknowledged.moveNext() ||
          acknowledged.current != '$sequence') {
        throw StateError('The receiver lost frame $sequence');
      }
    }));
  }
  await channel.dispose();
  exit(await receiver.exitCode);
}
