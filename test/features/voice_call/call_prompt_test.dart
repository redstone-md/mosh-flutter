import 'package:flutter_test/flutter_test.dart';

import 'call_confirmation_cases.dart' as call_confirmation;
import 'call_ringing_cases.dart' as call_ringing;

void main() {
  group('call_confirmation', call_confirmation.main);
  group('call_ringing', call_ringing.main);
}
