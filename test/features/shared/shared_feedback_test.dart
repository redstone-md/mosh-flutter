import 'package:flutter_test/flutter_test.dart';

import 'chat_error_banner_cases.dart' as chat_error_banner;
import 'persistence_warning_banner_cases.dart' as persistence_warning_banner;
import 'inline_error_cases.dart' as inline_error;

void main() {
  group('inline_error', inline_error.main);
  group('chat_error_banner', chat_error_banner.main);
  group('persistence_warning_banner', persistence_warning_banner.main);
}
