import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/onboarding/first_run_theme.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';

import '../../support/pump.dart';

void main() {
  testWidgets('invitation actions share typography and secondary emphasis',
      (tester) async {
    await _pump(tester);
    expect(find.byType(OutlinedButton), findsNWidgets(2));
    expect(find.byType(FilledButton), findsOneWidget);
    final primary = _label(tester, 'Open chat');
    for (final label in ['Copy link', 'Replace link']) {
      final secondary = _label(tester, label);
      expect(secondary.fontFamily, primary.fontFamily);
      expect(secondary.fontSize, primary.fontSize);
      expect(secondary.fontWeight, primary.fontWeight);
      expect(secondary.color, MoshColors.fg1);
      expect(tester.getSize(_button(label)).height,
          tester.getSize(_button('Open chat')).height);
    }
    expect(primary.fontWeight, FontWeight.w600);
    expect(primary.color, MoshColors.mossInk);
  });

  testWidgets('copy feedback preserves button styling and disabled actions',
      (tester) async {
    await _pump(tester);
    final before = _label(tester, 'Copy link');
    await _pump(tester, copied: true);
    expect(_label(tester, 'Copied'), before);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await _pump(tester, copied: true, busy: true);
    final buttons = tester.widgetList<ButtonStyleButton>(
        find.byWidgetPredicate((widget) => widget is ButtonStyleButton));
    expect(buttons.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('setup actions keep larger text and wrap within a narrow card',
      (tester) async {
    await _pump(tester, setup: true, width: 240);
    final primary = _label(tester, 'Open chat');
    expect(primary.fontSize, 15);
    expect(primary.fontWeight, FontWeight.w600);
    for (final label in ['Copy link', 'Replace link']) {
      expect(_label(tester, label).fontSize, primary.fontSize);
      expect(tester.getSize(_button(label)).height,
          tester.getSize(_button('Open chat')).height);
      expect(tester.getRect(_button(label)).right, lessThanOrEqualTo(520));
    }
    expect(tester.takeException(), isNull);
  });
}

TextStyle _label(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(find.text(label)).text.style!;

Finder _button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton));

Future<void> _pump(WidgetTester tester,
        {bool copied = false,
        bool busy = false,
        bool setup = false,
        double width = 520}) =>
    pumpScreen(
        tester,
        Theme(
            data: setup ? buildSetupTheme(moshThemeData) : moshThemeData,
            child: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: width,
                        child: InviteResult(
                            note: setup ? 'Share this invitation' : '',
                            uri: 'mosh://invite?session=alice',
                            copied: copied,
                            busy: busy,
                            onCopy: () {},
                            openLabel: 'Open chat',
                            onOpen: () {},
                            onReplace: () {}))))));
