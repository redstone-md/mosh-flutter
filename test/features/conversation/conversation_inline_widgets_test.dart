import 'package:flutter_test/flutter_test.dart';

import 'unread_badge_cases.dart' as unread_badge;
import 'typing_hint_cases.dart' as typing_hint;
import 'conversation_search_box_cases.dart' as conversation_search_box;

void main() {
  group('unread_badge', unread_badge.main);
  group('typing_hint', typing_hint.main);
  group('conversation_search_box', conversation_search_box.main);
}
