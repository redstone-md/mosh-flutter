import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/conversation/chat_header_menu.dart';

import '../support/pump.dart';

Future<void> _pumpMenu(
    WidgetTester tester, List<ChatHeaderMenuAction> actions) async {
  await pumpScreen(
      tester,
      Theme(
        data: buildMoshTheme().copyWith(platform: TargetPlatform.windows),
        child: Scaffold(
            body: Align(
          alignment: Alignment.topRight,
          child: Builder(
              builder: (context) => ChatHeaderMenu(
                  actions: actions, l: AppLocalizations.of(context)!)),
        )),
      ));
}

void main() {
  // Regression: one short action made a menu as narrow as its label.
  testWidgets('a menu keeps its width and sets the destructive action apart',
      (tester) async {
    await _pumpMenu(tester, [
      ChatHeaderMenuAction(
          label: 'Files', icon: MoshIcons.attach, onSelect: () {}),
      ChatHeaderMenuAction(
          label: 'Leave', icon: MoshIcons.leave, danger: true, onSelect: () {}),
    ]);
    await tester.tap(find.byIcon(MoshIcons.more));
    await tester.pumpAndSettle();

    final files = tester.getRect(find.widgetWithText(MenuItemButton, 'Files'));
    final leave = tester.getRect(find.widgetWithText(MenuItemButton, 'Leave'));
    expect(files.width, 232 - 16);
    final line = tester.getRect(find.byType(Divider));
    expect(line.top, greaterThanOrEqualTo(files.bottom));
    expect(line.bottom, lessThanOrEqualTo(leave.top));
  });

  testWidgets('enabled action closes the popover and runs once',
      (tester) async {
    var calls = 0;
    await _pumpMenu(tester, [
      ChatHeaderMenuAction(
          label: 'Delete chat',
          icon: MoshIcons.delete,
          danger: true,
          onSelect: () => calls++),
    ]);
    await tester.tap(find.byIcon(MoshIcons.more));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Delete chat'), findsNothing);
  });

  testWidgets('disabled actions cannot run; Escape restores trigger focus',
      (tester) async {
    var calls = 0;
    await _pumpMenu(tester, [
      ChatHeaderMenuAction(
          label: 'Unavailable action',
          icon: MoshIcons.link,
          disabled: true,
          onSelect: () => calls++),
      ChatHeaderMenuAction(
          label: 'Copy invitation', icon: MoshIcons.copy, onSelect: () {}),
    ]);
    await tester.tap(find.byIcon(MoshIcons.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unavailable action'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Copy invitation'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Copy invitation'), findsNothing);
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).focusNode!.hasFocus,
        isTrue);
  });

  testWidgets('an empty action list leaves the trigger disabled',
      (tester) async {
    await _pumpMenu(tester, []);
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });
}
