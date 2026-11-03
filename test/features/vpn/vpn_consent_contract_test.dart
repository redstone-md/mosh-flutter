// Related VPN contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'vpn_consent_modal_cases.dart' as vpn_consent_modal;
import 'network_choice_prompt_cases.dart' as network_choice_prompt;
import 'network_choice_remount_cases.dart' as network_choice_remount;

void main() {
  group('vpn_consent_modal', vpn_consent_modal.main);
  group('network_choice_prompt', network_choice_prompt.main);
  group('network_choice_remount', network_choice_remount.main);
}
