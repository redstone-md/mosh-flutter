import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_transition.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../../support/first_run.dart';
import '../../support/first_run_preview.dart';

void main() {
  for (final size in [const Size(1280, 680), const Size(1920, 1080)]) {
    testWidgets('the name step stands in the middle at $size', (tester) async {
      final harness =
          FirstRunHarness(profile: const FirstRunProfile(displayName: 'Лена'));
      await harness.pump(tester, size: size);
      final step = tester.getRect(setupStep);
      final viewport = _viewport(tester);
      expect(step.center.dx, closeTo(viewport.center.dx, 1));
      expect(step.center.dy, closeTo(viewport.center.dy, 1));
      // 480 px of content and the step's own padding on the desktop.
      expect(step.width, lessThanOrEqualTo(480 + 48));
    });
  }

  testWidgets('a phone starts the name step at the top of the screen',
      (tester) async {
    final harness =
        FirstRunHarness(profile: const FirstRunProfile(displayName: 'Лена'));
    await harness.pump(tester, size: const Size(390, 844));
    final step = tester.getRect(setupStep);
    final viewport = _viewport(tester);
    expect(step.top, viewport.top);
    expect(step.width, viewport.width);
  });

  testWidgets('a step taller than the window scrolls', (tester) async {
    final harness =
        FirstRunHarness(profile: const FirstRunProfile(displayName: 'Yuna'));
    await harness.pump(tester, size: const Size(320, 568), scale: 2);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.getRect(setupStep).top, _viewport(tester).top);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.step, SetupStep.device);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 680), const Size(900, 700)]) {
    for (final step in SetupStep.values) {
      testWidgets('$step fits the first viewport at $size', (tester) async {
        await prepareSetupPreview(tester);
        final harness = FirstRunHarness(
            profile: FirstRunProfile(displayName: 'Лена', step: step));
        await harness.pump(tester, size: size);
        await harness.container
            .read(localeProvider.notifier)
            .setLocale(const Locale('ru'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scroll =
            tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(scroll.position.maxScrollExtent, closeTo(0, 1));
        expect(
            tester.getRect(setupStep).bottom, lessThanOrEqualTo(size.height));
        await saveSetupPreview(tester,
            'first-run-${step.name}-${size.width.toInt()}x${size.height.toInt()}');
      });
    }
  }

  testWidgets('the step stays in the middle as the window grows',
      (tester) async {
    await prepareSetupPreview(tester);
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester, size: const Size(1280, 680));
    final small = tester.getRect(setupStep);
    expect(small.center.dy, closeTo(_viewport(tester).center.dy, 1));
    await saveSetupPreview(tester, 'first-run-centered-680');
    tester.view.physicalSize = const Size(1280, 1080);
    await tester.pumpAndSettle();
    final large = tester.getRect(setupStep);
    expect(large.center.dy, closeTo(_viewport(tester).center.dy, 1));
    expect(large.top, greaterThan(small.top));
    expect(large.size, small.size);
    await saveSetupPreview(tester, 'first-run-centered-1080');
  });

  testWidgets('resizing to a phone and back preserves the unsaved name',
      (tester) async {
    await prepareSetupPreview(tester);
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester, size: const Size(1280, 680));
    await harness.container
        .read(localeProvider.notifier)
        .setLocale(const Locale('ru'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Лена');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Лена');
    await tester.ensureVisible(find.byType(FilledButton));
    expect(tester.takeException(), isNull);
    await saveSetupPreview(tester, 'first-run-phone');
    tester.view.physicalSize = const Size(1280, 680);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Лена');
  });

  testWidgets('keyboard leaves the name and continue action reachable',
      (tester) async {
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester, size: const Size(390, 844));
    await tester.enterText(find.byType(TextFormField), 'Лена');
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    final action = tester.getRect(find.byType(FilledButton));
    expect(action.bottom, lessThanOrEqualTo(844 - 360));
    expect(action.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.displayName, 'Лена');
    expect(harness.store.profile!.step, SetupStep.device);
  });
}

/// The room the wizard has under the title bar.
Rect _viewport(WidgetTester tester) =>
    tester.getRect(find.byType(SetupStableLayout));
