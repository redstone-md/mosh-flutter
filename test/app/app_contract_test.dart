// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'mosh_controls_cases.dart' as mosh_controls;
import 'mosh_theme_cases.dart' as mosh_theme;
import 'distribution_channel_cases.dart' as distribution_channel;

void main() {
  group('mosh_controls', mosh_controls.main);
  group('mosh_theme', mosh_theme.main);
  group('distribution_channel', distribution_channel.main);
}
