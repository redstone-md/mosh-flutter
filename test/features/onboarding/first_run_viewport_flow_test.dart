// Related onboarding contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'first_run_shell_transition_cases.dart' as first_run_shell_transition;
import 'first_run_viewports_cases.dart' as first_run_viewports;
import 'first_run_device_pending_cases.dart' as first_run_device_pending;

void main() {
  group('first_run_shell_transition', first_run_shell_transition.main);
  group('first_run_viewports', first_run_viewports.main);
  group('first_run_device_pending', first_run_device_pending.main);
}
