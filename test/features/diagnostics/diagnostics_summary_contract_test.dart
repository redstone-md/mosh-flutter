import 'package:flutter_test/flutter_test.dart';

import 'channel_group_diagnostics_cases.dart' as channel_group_diagnostics;
import 'summary_card_cases.dart' as summary_card;
import 'diagnostics_sections_cases.dart' as diagnostics_sections;
import 'diagnostics_summary_cases.dart' as diagnostics_summary;

void main() {
  group('channel_group_diagnostics', channel_group_diagnostics.main);
  group('summary_card', summary_card.main);
  group('diagnostics_sections', diagnostics_sections.main);
  group('diagnostics_summary', diagnostics_summary.main);
}
