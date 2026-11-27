// IVO-50: the start menu answers the pointer quietly: a row takes the state
// layer of any control and nothing leans or drifts.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/start_row.dart';
import '../../support/pump.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = const Size(1200, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpScreen(tester, Scaffold(body: Center(child: child)));
}

Widget _row({VoidCallback? onTap}) => SizedBox(
      width: 480,
      child: StartRow(
        icon: MoshIcons.link,
        accent: MoshColors.dark.onSurfaceVariant,
        title: 'Join with a link',
        line: 'Use an invite a contact sent you',
        onTap: onTap ?? () {},
      ),
    );

void main() {
  testWidgets('Enter on a focused row opens it', (tester) async {
    var taps = 0;
    await _pump(tester, _row(onTap: () => taps++));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });
}
