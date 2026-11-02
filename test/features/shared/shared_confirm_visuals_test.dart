import 'package:flutter_test/flutter_test.dart';

import 'confirm_dialog_cases.dart' as confirm_dialog;
import 'modal_focus_trap_cases.dart' as modal_focus_trap;
import 'on_accent_contrast_cases.dart' as on_accent_contrast;

void main() {
  group('confirm_dialog', confirm_dialog.main);
  group('modal_focus_trap', modal_focus_trap.main);
  group('on_accent_contrast', on_accent_contrast.main);
}
