import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/main.dart';

void main() {
  testWidgets('MoshApp shows version string', (tester) async {
    await tester.pumpWidget(const MoshApp());

    expect(find.text('Mosh'), findsOneWidget);
    expect(find.text('Mosh 0.8.0-dev'), findsOneWidget);
  });
}