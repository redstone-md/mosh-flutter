// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'call_capture_config_cases.dart' as call_capture_config;
import 'record_voice_capture_cases.dart' as record_voice_capture;
import 'voice_capture_cases.dart' as voice_capture;
import 'voice_playback_cases.dart' as voice_playback;

void main() {
  group('call_capture_config', call_capture_config.main);
  group('record_voice_capture', record_voice_capture.main);
  group('voice_capture', voice_capture.main);
  group('voice_playback', voice_playback.main);
}
