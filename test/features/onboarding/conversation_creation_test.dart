// Related onboarding contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'chat_create_screen_cases.dart' as chat_create_screen;
import 'group_create_screen_cases.dart' as group_create_screen;
import 'channel_join_screen_cases.dart' as channel_join_screen;
import 'inline_error_cases.dart' as inline_error;

void main() {
  group('chat_create_screen', chat_create_screen.main);
  group('group_create_screen', group_create_screen.main);
  group('channel_join_screen', channel_join_screen.main);
  group('inline_error', inline_error.main);
}
