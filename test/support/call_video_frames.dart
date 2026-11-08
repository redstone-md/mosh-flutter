import 'dart:typed_data';

import 'package:mosh/src/features/voice_call/call_video_frame.dart';

CallVideoFrame testCallVideoFrame(int sequence,
        {bool local = false, int sourceAgeMs = 0}) =>
    CallVideoFrame(
        sessionId: 'dm',
        callId: 'call',
        sequence: sequence,
        width: 2,
        height: 2,
        local: local,
        sourceAgeMs: sourceAgeMs,
        pixels: Uint8List.fromList([
          255,
          0,
          0,
          255,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          255
        ]));
