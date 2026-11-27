import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_layout.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/onboarding/first_run_transition.dart';
import 'package:mosh/src/features/device_link/device_link_import_form.dart';

import '../../support/first_run.dart';

void main() {
  // The desktop window is tall enough for the device step under the top the
  // name step takes; a shorter one raises the top to make room.
  for (final size in [const Size(1280, 1400), const Size(390, 844)]) {
    testWidgets('step changes keep the visible shell mounted at $size',
        (tester) async {
      final harness =
          FirstRunHarness(profile: const FirstRunProfile(displayName: 'Yuna'));
      await harness.pump(tester, size: size);
      final progress = find.byType(SetupProgress);
      final originalStep = tester.renderObject(setupStep);
      final originalProgress = tester.element(progress);
      // Steps differ in height: the shell is where the step starts and how
      // wide it is, not how far down it reaches.
      final stepRect = tester.getRect(setupStep);
      final progressRect = tester.getRect(progress);
      for (final step in [
        SetupStep.device,
        SetupStep.network,
        SetupStep.name
      ]) {
        await harness.container
            .read(firstRunProfileProvider.notifier)
            .goTo(step);
        await tester.pump();
        await tester.pump();
        for (final frame in [
          const Duration(milliseconds: 60),
          const Duration(milliseconds: 60),
          const Duration(milliseconds: 160)
        ]) {
          await tester.pump(frame);
          expect(tester.renderObject(setupStep), same(originalStep));
          expect(tester.element(progress), same(originalProgress));
          expect(tester.getRect(setupStep).topLeft, stepRect.topLeft);
          expect(tester.getRect(setupStep).width, stepRect.width);
          expect(tester.getRect(progress), progressRect);
          expect(
              find.ancestor(
                  of: progress, matching: find.byType(SetupStepTransition)),
              findsNothing);
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(setupStep).topLeft, stepRect.topLeft);
        expect(tester.getRect(progress), progressRect);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('returning to device linking keeps the unfinished importer',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Yuna', step: SetupStep.device));
    await harness.pump(tester);
    const uri = 'mosh://device-link?invite=unfinished';
    await tester.enterText(find.byType(TextField), uri);
    final importer = tester.state(find.byType(DeviceLinkImportForm));
    await tapSetup(tester, 'Back');
    await tapSetup(tester, 'Continue');
    expect(tester.state(find.byType(DeviceLinkImportForm)), same(importer));
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, uri);
    expect(tester.takeException(), isNull);
  });
}
