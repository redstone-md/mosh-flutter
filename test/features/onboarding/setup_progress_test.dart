// Contracts of the Setup progress and Link step of the Wizard step card
// (MOSH-138): what tells a done step from the current one and from one
// ahead, in both palettes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/device_link/device_link_steps.dart';
import 'package:mosh/src/features/onboarding/first_run_layout.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/shared/step_mark.dart';
import 'package:mosh/src/rust/device_link/types.dart';

Future<void> _pump(WidgetTester tester, MoshColors colors, Widget child) =>
    tester.pumpWidget(MaterialApp(
      theme: buildMoshTheme(colors),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ));

BoxDecoration _plate(WidgetTester tester, int number) => tester
    .widget<Container>(find.descendant(
        of: find.byWidgetPredicate(
            (widget) => widget is StepMark && widget.number == number),
        matching: find.byType(Container)))
    .decoration! as BoxDecoration;

Color? _ink(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color;

void main() {
  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    testWidgets(
        '$palette: setup ticks what is done, fills the current step and '
        'outlines what is ahead', (tester) async {
      await _pump(tester, colors, const SetupProgress(step: SetupStep.device));

      expect(_plate(tester, 1).color, colors.secondaryContainer);
      expect(
          find.descendant(
              of: find.byType(StepMark).first,
              matching: find.byIcon(MoshIcons.check)),
          findsOneWidget);
      expect(find.text('1'), findsNothing);

      expect(_plate(tester, 2).color, colors.primary);
      expect(_ink(tester, '2'), colors.onPrimary);

      expect(_plate(tester, 3).color, isNull);
      expect(_plate(tester, 3).border, Border.all(color: colors.outline));
      expect(_ink(tester, '3'), colors.onSurfaceMuted);

      // Only the step ahead is named quietly.
      expect(_ink(tester, 'Name'), colors.onSurface);
      expect(_ink(tester, 'Device'), colors.onSurface);
      expect(_ink(tester, 'Network'), colors.onSurfaceMuted);
    });

    testWidgets('$palette: device linking counts its steps the same way',
        (tester) async {
      await _pump(
          tester,
          colors,
          const DeviceLinkSteps(
              role: DeviceLinkRole.joining,
              phase: DeviceLinkPhase.awaitingConfirmation));
      expect(_plate(tester, 1).color, colors.secondaryContainer);
      expect(_plate(tester, 2).color, colors.primary);
      expect(_plate(tester, 3).color, isNull);
      // A link step's mark is the smaller one.
      expect(tester.getSize(find.byType(StepMark).first), const Size(24, 24));
    });
  }

  testWidgets('a mark keeps its size and its number under enlarged text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
        tester, MoshColors.dark, const SetupProgress(step: SetupStep.name));
    for (final mark in find.byType(StepMark).evaluate()) {
      expect(mark.size, const Size(32, 32));
    }
    expect(tester.takeException(), isNull);
  });
}
