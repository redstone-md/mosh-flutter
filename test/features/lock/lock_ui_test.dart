// Related lock UI contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'mosh_lock_screen_cases.dart' as mosh_lock_screen;
import 'mosh_lock_screen_errors_cases.dart' as mosh_lock_screen_errors;
import 'lock_language_cases.dart' as lock_language;

void main() {
  group('mosh_lock_screen', mosh_lock_screen.main);
  group('mosh_lock_screen_errors', mosh_lock_screen_errors.main);
  group('lock_language', lock_language.main);
}
