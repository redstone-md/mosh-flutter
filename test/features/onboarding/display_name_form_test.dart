import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/display_name_form.dart';

import '../../support/pump.dart';

void main() {
  testWidgets('a pasted name keeps the whole characters that fit and saves',
      (tester) async {
    String? saved;
    await pumpScreen(
        tester,
        Scaffold(
            body: DisplayNameForm(
                initialName: '',
                actionLabel: 'Save',
                onSave: (name) async => saved = name)));

    // A family emoji is 7 code points: 9 of them fill 63, the 10th does not fit.
    await tester.enterText(find.byType(TextFormField), '👨‍👩‍👧‍👦' * 10);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, '👨‍👩‍👧‍👦' * 9);
  });
}
