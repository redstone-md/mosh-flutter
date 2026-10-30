// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'voice_call_session_provider_cases.dart' as voice_call_session_provider;
import 'android_call_answer_cases.dart' as android_call_answer;
import 'production_provider_overrides_cases.dart'
    as production_provider_overrides;
import 'persistence_warning_provider_cases.dart'
    as persistence_warning_provider;

void main() {
  group('voice_call_session_provider', voice_call_session_provider.main);
  group('android_call_answer', android_call_answer.main);
  group('production_provider_overrides', production_provider_overrides.main);
  group('persistence_warning_provider', persistence_warning_provider.main);
}
