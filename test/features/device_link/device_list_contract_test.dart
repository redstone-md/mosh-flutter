import 'package:flutter_test/flutter_test.dart';

import 'device_list_cases.dart' as device_list;
import 'device_revocation_cases.dart' as device_revocation;

void main() {
  group('device_list', device_list.main);
  group('device_revocation', device_revocation.main);
}
