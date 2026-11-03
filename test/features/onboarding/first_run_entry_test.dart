// Related onboarding contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'first_run_wizard_cases.dart' as first_run_wizard;
import 'pending_invitation_cases.dart' as pending_invitation;

void main() {
  group('first_run_wizard', first_run_wizard.main);
  group('pending_invitation', pending_invitation.main);
}
