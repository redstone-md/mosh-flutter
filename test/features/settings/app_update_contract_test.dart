// Related update contracts share a process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'app_release_provider_cases.dart' as app_release_provider;
import 'app_update_apply_cases.dart' as app_update_apply;
import 'app_update_download_cases.dart' as app_update_download;

void main() {
  group('app_release_provider', app_release_provider.main);
  group('app_update_apply', app_update_apply.main);
  group('app_update_download', app_update_download.main);
}
