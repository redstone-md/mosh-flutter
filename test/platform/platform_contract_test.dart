// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'android_background_dek_storage_cases.dart'
    as android_background_dek_storage;
import 'android_waiting_platform_cases.dart' as android_waiting_platform;
import 'mobile_dek_cases.dart' as mobile_dek;
import 'app_data_dir_cases.dart' as app_data_dir;
import 'mic_permission_config_cases.dart' as mic_permission_config;

void main() {
  group('android_background_dek_storage', android_background_dek_storage.main);
  group('android_waiting_platform', android_waiting_platform.main);
  group('mobile_dek', mobile_dek.main);
  group('app_data_dir', app_data_dir.main);
  group('mic_permission_config', mic_permission_config.main);
}
