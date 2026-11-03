// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'rail_entry_search_cases.dart' as rail_entry_search;
import 'revoked_dm_badges_cases.dart' as revoked_dm_badges;

void main() {
  group('rail_entry_search', rail_entry_search.main);
  group('revoked_dm_badges', revoked_dm_badges.main);
}
