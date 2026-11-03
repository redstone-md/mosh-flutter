import 'package:flutter_test/flutter_test.dart';

import 'incoming_call_modal_cases.dart' as incoming_call_modal;
import 'outgoing_call_modal_cases.dart' as outgoing_call_modal;
import 'call_confirmation_cases.dart' as call_confirmation;
import 'call_ringing_cases.dart' as call_ringing;

void main() {
  group('incoming_call_modal', incoming_call_modal.main);
  group('outgoing_call_modal', outgoing_call_modal.main);
  group('call_confirmation', call_confirmation.main);
  group('call_ringing', call_ringing.main);
}
