// The phone's page header at a large text size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/page_header.dart';

void main() {
  testWidgets('at twice the text size the way back stays beside the name',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMoshTheme(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: PageHeader(
              title: 'Sound and video',
              line: 'Changes are saved as you make them',
              onBack: () {}),
        ),
      ),
    ));
    final arrow = tester.getCenter(find.byIcon(MoshIcons.back)).dy;
    final name = tester.getRect(find.text('Sound and video'));
    expect((arrow - name.center.dy).abs(), lessThan(name.height / 4),
        reason: 'the arrow is level with the name, not with name and line');
  });
}
