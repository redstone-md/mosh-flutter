// While members are being added the button is Loading: it keeps its label,
// so the row does not lose its meaning, and a second press adds nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/org/org_add_missing_banner.dart';

void main() {
  Future<int Function()> pumpBanner(WidgetTester tester,
      {required bool busy}) async {
    var added = 0;
    await tester.pumpWidget(MaterialApp(
      theme: moshThemeData,
      home: Scaffold(
        body: OrgAddMissingBanner(
          count: 2,
          busy: busy,
          onAdd: () => added++,
          missingOne: 'member is not in this group',
          missingMany: 'members are not in this group',
          addLabel: 'Add to group',
        ),
      ),
    ));
    return () => added;
  }

  testWidgets('a loading Add button keeps its label and ignores the press',
      (tester) async {
    final added = await pumpBanner(tester, busy: true);

    expect(find.text('Add to group'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Add to group'));
    expect(added(), 0);
  });

  testWidgets('an idle Add button adds the missing members', (tester) async {
    final added = await pumpBanner(tester, busy: false);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Add to group'));
    expect(added(), 1);
  });
}
