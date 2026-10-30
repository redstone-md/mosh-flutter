// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'session_providers_cases.dart' as session_providers;
import 'chat_names_provider_cases.dart' as chat_names_provider;
import 'conversation_providers_cases.dart' as conversation_providers;
import 'notifications_provider_cases.dart' as notifications_provider;

void main() {
  group('session_providers', session_providers.main);
  group('chat_names_provider', chat_names_provider.main);
  group('conversation_providers', conversation_providers.main);
  group('notifications_provider', notifications_provider.main);
}
