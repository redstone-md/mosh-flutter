import 'package:flutter_test/flutter_test.dart';

import 'call_notification_focus_cases.dart' as call_notification_focus;
import 'call_notification_lifetime_cases.dart' as call_notification_lifetime;
import 'call_notification_retry_cases.dart' as call_notification_retry;

void main() {
  group('call_notification_focus', call_notification_focus.main);
  group('call_notification_lifetime', call_notification_lifetime.main);
  group('call_notification_retry', call_notification_retry.main);
}
