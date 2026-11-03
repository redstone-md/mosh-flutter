// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'call_window_frames_cases.dart' as call_window_frames;

import 'frame_codec_cases.dart' as frame_codec;
import 'frame_crypto_cases.dart' as frame_crypto;
import 'jitter_buffer_cases.dart' as jitter_buffer;
import 'call_drain_cases.dart' as call_drain;

void main() {
  group('call_window_frames', call_window_frames.main);
  group('frame_codec', frame_codec.main);
  group('frame_crypto', frame_crypto.main);
  group('jitter_buffer', jitter_buffer.main);
  group('call_drain', call_drain.main);
}
