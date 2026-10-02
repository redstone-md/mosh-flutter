import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_layout.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../../support/first_run.dart';
import '../../support/first_run_preview.dart';

void main() {
  for (final size in [const Size(1280, 680), const Size(900, 700)]) {
    for (final step in SetupStep.values) {
      testWidgets('$step fits the first viewport at $size', (tester) async {
        await prepareSetupPreview(tester);
        final harness = FirstRunHarness(
            profile: FirstRunProfile(displayName: 'Лена', step: step));
        await harness.pump(tester, size: size);
        harness.container
            .read(localeProvider.notifier)
            .setLocale(const Locale('ru'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scroll =
            tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(scroll.position.maxScrollExtent, closeTo(0, 1));
        expect(_card(tester).bottom, lessThanOrEqualTo(size.height));
        await saveSetupPreview(tester,
            'first-run-${step.name}-${size.width.toInt()}x${size.height.toInt()}');
      });
    }
  }

  testWidgets('card stays centered and illustration follows available height',
      (tester) async {
    await prepareSetupPreview(tester);
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester, size: const Size(1280, 680));
    final smallImage = tester.getSize(find.byType(Image));
    final smallCard = _card(tester);
    final smallViewport = _viewport(tester);
    expect(smallCard.center.dy, closeTo(smallViewport.center.dy, 1));
    await saveSetupPreview(tester, 'first-run-centered-680');
    tester.view.physicalSize = const Size(1280, 1080);
    await tester.pumpAndSettle();
    final largeCard = _card(tester);
    expect(largeCard.center.dy, closeTo(_viewport(tester).center.dy, 1));
    expect(tester.getSize(find.byType(Image)).height,
        greaterThan(smallImage.height));
    expect(largeCard.top, greaterThan(smallCard.top));
    expect(tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(52));
    await saveSetupPreview(tester, 'first-run-centered-1080');
  });

  testWidgets('resizing to one column preserves the unsaved name',
      (tester) async {
    await prepareSetupPreview(tester);
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester, size: const Size(1280, 680));
    harness.container
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
    expect(tester.getRect(find.byType(Image)).bottom,
        lessThan(tester.getRect(find.byType(TextFormField)).top));
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
    expect(action.height, greaterThanOrEqualTo(52));
    expect(tester.takeException(), isNull);
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.displayName, 'Лена');
    expect(harness.store.profile!.step, SetupStep.device);
  });
}

Rect _card(WidgetTester tester) => tester.getRect(find
    .ancestor(of: find.byType(SetupProgress), matching: find.byType(Container))
    .first);

Rect _viewport(WidgetTester tester) => tester.getRect(find
    .ancestor(
        of: find.byType(SetupProgress),
        matching: find.byType(SingleChildScrollView))
    .first);
