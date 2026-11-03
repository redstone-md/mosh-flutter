// Billing uses a real per-test loopback server. Keep Flutter's HTTP mock out
// of this runner; its lifecycle cases use provider containers only.
import 'package:flutter_test/flutter_test.dart';

import 'plus_lifecycle_cases.dart' as plus_lifecycle;
import 'plus_billing_cases.dart' as plus_billing;

void main() {
  group('plus_lifecycle', plus_lifecycle.main);
  group('plus_billing', plus_billing.main);
}
