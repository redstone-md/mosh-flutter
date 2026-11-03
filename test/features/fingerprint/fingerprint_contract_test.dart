import 'package:flutter_test/flutter_test.dart';

import 'fingerprint_emoji_cases.dart' as fingerprint_emoji;
import 'fingerprint_lock_cases.dart' as fingerprint_lock;

void main() {
  group('fingerprint_emoji', fingerprint_emoji.main);
  group('fingerprint_lock', fingerprint_lock.main);
}
