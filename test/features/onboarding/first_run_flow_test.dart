// Related onboarding contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'first_run_network_cases.dart' as first_run_network;
import 'first_run_transition_cases.dart' as first_run_transition;

void main() {
  group('first_run_network', first_run_network.main);
  group('first_run_transition', first_run_transition.main);
}
