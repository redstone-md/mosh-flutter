// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'call_window_frames_cases.dart' as call_window_frames;

void main() {
  group('call_window_frames', call_window_frames.main);
}
