import 'package:flutter_test/flutter_test.dart';

import 'call_overlay_cases.dart' as call_overlay;
import 'voice_call_layer_lifecycle_cases.dart' as voice_call_layer_lifecycle;
import 'call_view_command_cases.dart' as call_view_command;

void main() {
  group('call_overlay', call_overlay.main);
  group('voice_call_layer_lifecycle', voice_call_layer_lifecycle.main);
  group('call_view_command', call_view_command.main);
}
