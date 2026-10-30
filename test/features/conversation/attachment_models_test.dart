// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'attachment_preview_size_cases.dart' as attachment_preview_size;
import 'attachment_miniature_cache_cases.dart' as attachment_miniature_cache;
import 'clipboard_paste_handler_cases.dart' as clipboard_paste_handler;

void main() {
  group('attachment_preview_size', attachment_preview_size.main);
  group('attachment_miniature_cache', attachment_miniature_cache.main);
  group('clipboard_paste_handler', clipboard_paste_handler.main);
}
