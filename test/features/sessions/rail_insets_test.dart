// IVO-15: the chat list's right inset was twice its left one, and the
// filter chips started 2px right of the search field above them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';

import '../../support/rail.dart';

void main() {
  for (final (label, size) in [
    ('desktop', const Size(1200, 850)),
    ('phone', const Size(390, 844)),
  ]) {
    testWidgets('$label: rows sit as far from the right edge as the left',
        (tester) async {
      await pumpRail(tester, size: size);
      final rail = tester.getRect(find.byType(SessionsScreen));
      for (final part in [RailItem, RailNewButton, RailSettingsButton]) {
        final rect = tester.getRect(find.byType(part).first);
        expect(rail.right - rect.right, rect.left - rail.left, reason: '$part');
      }
    });

    testWidgets('$label: filter chips line up with the search field',
        (tester) async {
      await pumpRail(tester, size: size);
      final search =
          tester.getRect(find.byKey(const ValueKey('chat-list-search')));
      final chip = tester.getRect(find.byType(ChoiceChip).first);
      // A chip's tap target pads its painted pill vertically only.
      expect(chip.left, search.left);
    });
  }
}
