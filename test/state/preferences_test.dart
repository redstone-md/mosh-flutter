// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'locale_preference_cases.dart' as locale_preference;
import 'rail_layout_cases.dart' as rail_layout;

void main() {
  group('locale_preference', locale_preference.main);
  group('rail_layout', rail_layout.main);
}
