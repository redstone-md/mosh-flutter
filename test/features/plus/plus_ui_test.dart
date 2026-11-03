// Related Plus UI contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'plus_offer_cases.dart' as plus_offer;
import 'user_plus_badge_cases.dart' as user_plus_badge;
import 'plus_membership_only_cases.dart' as plus_membership_only;
import 'plus_settings_storage_cases.dart' as plus_settings_storage;

void main() {
  group('plus_offer', plus_offer.main);
  group('user_plus_badge', user_plus_badge.main);
  group('plus_membership_only', plus_membership_only.main);
  group('plus_settings_storage', plus_settings_storage.main);
}
