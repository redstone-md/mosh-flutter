// The Search field card: what the field offers while it is empty and while
// it holds a query, and that its quiet inks stay readable on its plate.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/search_field.dart';

import '../../support/contrast.dart';

Future<List<String>> _pump(WidgetTester tester,
    {MoshColors colors = MoshColors.dark, String? shortcut = 'Ctrl K'}) async {
  final reported = <String>[];
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: buildMoshTheme(colors),
    home: Scaffold(
      body: SearchField(
        controller: controller,
        hint: 'Search chats',
        onChanged: reported.add,
        shortcut: shortcut,
      ),
    ),
  ));
  return reported;
}

Color _ink(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!.color!;

void main() {
  testWidgets('a query swaps the shortcut for a button that clears it',
      (tester) async {
    final reported = await _pump(tester);
    expect(find.text('Ctrl K'), findsOneWidget);
    expect(find.byIcon(MoshIcons.close), findsNothing);

    await tester.enterText(find.byType(SearchField), 'cabin');
    await tester.pump();
    expect(find.text('Ctrl K'), findsNothing);

    await tester.tap(find.byIcon(MoshIcons.close));
    await tester.pump();
    expect(reported, ['cabin', '']);
    expect(find.text('cabin'), findsNothing);
    expect(find.text('Ctrl K'), findsOneWidget);
  });

  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    testWidgets('the hint and the shortcut read at 4.5:1 on the $palette plate',
        (tester) async {
      await _pump(tester, colors: colors);
      for (final text in ['Search chats', 'Ctrl K']) {
        expect(contrastRatio(_ink(tester, text), colors.surfaceContainerHigh),
            greaterThanOrEqualTo(4.5),
            reason: text);
      }
    });
  }
}
