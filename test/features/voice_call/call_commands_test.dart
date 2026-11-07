// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'call_control_gate_cases.dart' as call_control_gate;
import 'call_dialog_cases.dart' as call_dialog;

void main() {
  group('call_control_gate', call_control_gate.main);
  group('call_dialog', call_dialog.main);
}
