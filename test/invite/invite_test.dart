// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'invite_detection_cases.dart' as invite_detection;
import 'invite_uri_cases.dart' as invite_uri;
import 'compact_invite_cases.dart' as compact_invite;

void main() {
  group('invite_detection', invite_detection.main);
  group('invite_uri', invite_uri.main);
  group('compact_invite', compact_invite.main);
}
