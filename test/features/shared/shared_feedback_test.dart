import 'package:flutter_test/flutter_test.dart';

import 'async_switch_tile_cases.dart' as async_switch_tile;
import 'chat_error_banner_cases.dart' as chat_error_banner;
import 'persistence_warning_banner_cases.dart' as persistence_warning_banner;
import 'inline_error_cases.dart' as inline_error;

void main() {
  group('inline_error', inline_error.main);
  group('async_switch_tile', async_switch_tile.main);
  group('chat_error_banner', chat_error_banner.main);
  group('persistence_warning_banner', persistence_warning_banner.main);
}
