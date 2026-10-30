// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'attachment_previews_cases.dart' as attachment_previews;
import 'preview_color_profile_cases.dart' as preview_color_profile;
import 'attachment_preview_colors_cases.dart' as attachment_preview_colors;

void main() {
  group('attachment_previews', attachment_previews.main);
  group('preview_color_profile', preview_color_profile.main);
  group('attachment_preview_colors', attachment_preview_colors.main);
}
