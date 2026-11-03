// Related VPN contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'bind_interface_field_cases.dart' as bind_interface_field;
import 'bind_interface_restart_cases.dart' as bind_interface_restart;

void main() {
  group('bind_interface_field', bind_interface_field.main);
  group('bind_interface_restart', bind_interface_restart.main);
}
