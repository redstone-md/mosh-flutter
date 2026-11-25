import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';

import '../../support/pump.dart';

void main() {
  testWidgets('only a dialog without answers of its own has a close button',
      (tester) async {
    var closed = 0;
    await pumpScreen(
        tester,
        MoshDialog(
            title: 'Call devices',
            closeLabel: 'Close',
            onCancel: () => closed++));
    await tester.tap(find.byTooltip('Close'));
    expect(closed, 1);

    await pumpScreen(
        tester,
        MoshDialog(
          title: 'Leave #photography?',
          closeLabel: 'Close',
          onCancel: () {},
          actions: [TextButton(onPressed: () {}, child: const Text('Cancel'))],
        ));
    expect(find.byTooltip('Close'), findsNothing);
  });

  for (final (device, platform, stacked) in [
    ('the phone', TargetPlatform.android, true),
    ('the desktop', TargetPlatform.windows, false),
  ]) {
    testWidgets(
        'answers marked as long ${stacked ? 'stack' : 'share a line'} on $device',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildMoshTheme(MoshColors.dark, platform),
        home: MoshDialog(
          title: 'A VPN is carrying Mosh’s traffic',
          closeLabel: 'Cancel',
          stackOnPhone: true,
          onCancel: () {},
          actions: [
            TextButton(onPressed: () {}, child: const Text('Keep')),
            FilledButton(onPressed: () {}, child: const Text('Go')),
          ],
        ),
      ));

      final leave = tester.getRect(find.byType(TextButton));
      final go = tester.getRect(find.byType(FilledButton));
      if (stacked) {
        // The main answer on top, both as wide as the dialog allows.
        expect(go.bottom, lessThanOrEqualTo(leave.top));
        expect(go.width, leave.width);
      } else {
        // The answer that goes on at the right.
        expect(go.left, greaterThanOrEqualTo(leave.right));
        expect(go.center.dy, leave.center.dy);
      }
    });
  }

  testWidgets('a second Escape during close preserves the underlying page',
      (tester) async {
    await pumpScreen(tester, Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                          body: TextButton(
                              onPressed: () => showMoshDialog<void>(
                                  context: context,
                                  builder: (_) => const MoshDialog(
                                      title: 'Dialog title',
                                      closeLabel: 'Close')),
                              child: const Text('Conversation page'))))),
              child: const Text('Enter chat')));
    }));
    await tester.tap(find.text('Enter chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversation page'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Conversation page'), findsOneWidget);
    expect(find.text('Dialog title'), findsNothing);
  });

  testWidgets('dialog traps Tab focus and returns it to the opening control', (
    tester,
  ) async {
    final trigger = FocusNode();
    addTearDown(trigger.dispose);
    await _mount(tester, trigger: trigger);
    trigger.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(trigger.hasFocus, isFalse);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(trigger.hasFocus, isFalse);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Dialog title'), findsNothing);
    expect(trigger.hasFocus, isTrue);
  });

  testWidgets('modal enters from .96 and leaves within 150ms', (tester) async {
    await _mount(tester);
    await tester.tap(find.text('Open'));
    await tester.pump();
    final scale = find.ancestor(
      of: find.byType(MoshDialog),
      matching: find.byType(ScaleTransition),
    );
    expect(tester.widget<ScaleTransition>(scale).scale.value, .96);
    await tester.pumpAndSettle();
    expect(tester.widget<ScaleTransition>(scale).scale.value, 1);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final fade = find.ancestor(
      of: find.byType(MoshDialog),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    expect(tester.widget<ScaleTransition>(scale).scale.value, .96);
    // The ticker finalizes at the frame after its exact duration boundary.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Dialog title'), findsNothing);
  });

  testWidgets('reduced motion opens and dismisses without a transition', (
    tester,
  ) async {
    await _mount(tester, reducedMotion: true);
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Dialog title'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(MoshDialog),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Dialog title'), findsNothing);
  });

  testWidgets('long content and actions fit a narrow enlarged-text dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: MoshDialog(
          title: 'A longer dialog title',
          closeLabel: 'Cancel',
          onCancel: () {},
          content: Text(List.filled(30, 'Readable content.').join(' ')),
          actions: [
            TextButton(onPressed: () {}, child: const Text('Cancel')),
            FilledButton(onPressed: () {}, child: const Text('Confirm action')),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final card = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first;
    expect(tester.getSize(card).width, lessThanOrEqualTo(308));
  });
}

Future<void> _mount(
  WidgetTester tester, {
  FocusNode? trigger,
  bool reducedMotion = false,
}) =>
    pumpScreen(
      tester,
      MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              focusNode: trigger,
              onPressed: () => showMoshDialog<void>(
                context: context,
                builder: (context) => MoshDialog(
                  title: 'Dialog title',
                  closeLabel: 'Close',
                  content: const Text('Dialog body'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
