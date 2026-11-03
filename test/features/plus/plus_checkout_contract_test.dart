// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'plus_mainnet_catalog_cases.dart' as plus_mainnet_catalog;
import 'plus_mainnet_polling_cases.dart' as plus_mainnet_polling;
import 'plus_mainnet_fulfillment_cases.dart' as plus_mainnet_fulfillment;
import 'plus_mainnet_retry_cases.dart' as plus_mainnet_retry;

void main() {
  group('plus_mainnet_catalog', plus_mainnet_catalog.main);
  group('plus_mainnet_polling', plus_mainnet_polling.main);
  group('plus_mainnet_fulfillment', plus_mainnet_fulfillment.main);
  group('plus_mainnet_retry', plus_mainnet_retry.main);
}
