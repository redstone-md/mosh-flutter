// The avatar's plate is picked per contact: one name keeps one plate
// wherever it is drawn, names spread over the four plates, and whatever
// stands on a plate reads on it in both palettes.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

import '../../support/contrast.dart';
import '../../support/pump.dart';

Color _plateOf(WidgetTester tester, Finder avatar) => tester
    .widget<CircleAvatar>(
        find.descendant(of: avatar, matching: find.byType(CircleAvatar)))
    .backgroundColor!;

void main() {
  test('a name keeps its plate and names spread over all four', () {
    const colors = MoshColors.dark;
    // Pinned values: a change of the pick would recolour every contact.
    expect(avatarPlate(colors, 'Alice Brown'), colors.avatar4);
    expect(avatarPlate(colors, 'Leo Park'), colors.avatar2);
    final plates = {
      for (final name in ['Alice', 'Bob', 'Carol', 'Dan', 'Erin', 'Frank'])
        avatarPlate(colors, name),
    };
    expect(plates, hasLength(4));
  });

  testWidgets('a contact has the same plate in a row and beside a message',
      (tester) async {
    await pumpScreen(
        tester,
        const Scaffold(
            body: Column(children: [
          Avatar(key: ValueKey('message'), name: 'Alice Brown'),
          ConversationKindAvatar(
              kind: ConversationKind.dm, name: 'Alice Brown'),
          Avatar(key: ValueKey('other'), name: 'Leo Park'),
        ])));

    final beside = _plateOf(tester, find.byKey(const ValueKey('message')));
    expect(_plateOf(tester, find.byType(ConversationKindAvatar)), beside);
    expect(
        _plateOf(tester, find.byKey(const ValueKey('other'))), isNot(beside));
  });

  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    testWidgets('initials and a group sign read on their plates, $palette',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildMoshTheme(colors),
        home: const Scaffold(
            body: Column(children: [
          Avatar(name: 'Alice Brown'),
          Avatar(name: 'Design team', sign: MoshIcons.group),
        ])),
      ));

      final initials =
          tester.renderObject<RenderParagraph>(find.text('AB')).text.style!;
      expect(
          contrastRatio(initials.color!,
              _plateOf(tester, find.widgetWithText(Avatar, 'AB'))),
          greaterThanOrEqualTo(4.5));
      final sign = tester.widget<Icon>(find.byIcon(MoshIcons.group));
      expect(
          contrastRatio(sign.color!,
              _plateOf(tester, find.widgetWithIcon(Avatar, MoshIcons.group))),
          greaterThanOrEqualTo(4.5));
      expect(find.text('DT'), findsNothing);
    });
  }
}
