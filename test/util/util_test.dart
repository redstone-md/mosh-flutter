// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'format_cases.dart' as format;
import 'format_bytes_cases.dart' as format_bytes;
import 'unread_cases.dart' as unread;

void main() {
  group('format', format.main);
  group('format_bytes', format_bytes.main);
  group('unread', unread.main);
}
