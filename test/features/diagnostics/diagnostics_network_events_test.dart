import 'package:flutter_test/flutter_test.dart';

import 'mesh_diagnostics_cases.dart' as mesh_diagnostics;
import 'event_log_cases.dart' as event_log;

void main() {
  group('mesh_diagnostics', mesh_diagnostics.main);
  group('event_log', event_log.main);
}
