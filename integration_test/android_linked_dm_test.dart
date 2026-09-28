import 'package:integration_test/integration_test.dart';

import 'support/linked_dm_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  linkedDmTest(android: true);
}
