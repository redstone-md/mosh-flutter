// Related onboarding contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'first_run_hierarchy_cases.dart' as first_run_hierarchy;
import 'first_run_responsive_cases.dart' as first_run_responsive;

void main() {
  group('first_run_hierarchy', first_run_hierarchy.main);
  group('first_run_responsive', first_run_responsive.main);
}
