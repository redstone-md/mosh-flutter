// Related onboarding contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'start_menu_cases.dart' as start_menu;
import 'start_menu_layout_cases.dart' as start_menu_layout;
import 'start_hover_cases.dart' as start_hover;
import 'new_session_panel_cases.dart' as new_session_panel;
import 'invite_result_cases.dart' as invite_result;

void main() {
  group('start_menu', start_menu.main);
  group('start_menu_layout', start_menu_layout.main);
  group('start_hover', start_hover.main);
  group('new_session_panel', new_session_panel.main);
  group('invite_result', invite_result.main);
}
