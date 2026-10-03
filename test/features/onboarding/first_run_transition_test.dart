import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_device_step.dart';
import 'package:mosh/src/features/onboarding/first_run_layout.dart';
import 'package:mosh/src/features/onboarding/first_run_network_step.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/onboarding/first_run_transition.dart';

import '../../support/first_run.dart';
import '../../support/first_run_preview.dart';

void main() {
  for (final step in SetupStep.values) {
    testWidgets('$step restores without an entrance animation', (tester) async {
      await _pump(tester, step, settle: false);
      expect(_fade(tester), 1);
      expect(_position(tester), Offset.zero);
      expect(_blocked(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 40));
      expect(_fade(tester), 1);
      expect(_position(tester), Offset.zero);
      expect(_blocked(tester), isFalse);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Continue crossfades the content without a blank interval',
      (tester) async {
    final harness = await _pump(tester, SetupStep.name);
    await tester.enterText(find.byType(TextFormField), 'Yuna');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();
    expect(harness.store.profile!.displayName, 'Yuna');
    expect(harness.store.profile!.step, SetupStep.device);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byType(FirstRunDeviceStep), findsOneWidget);
    expect(_blocked(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 40));
    expect(_fade(tester), inExclusiveRange(0, 1));
    expect(_position(tester).dx, greaterThan(0));
    expect(_fadeFor(tester, SetupStep.name), inExclusiveRange(0, 1));
    expect(_positionFor(tester, SetupStep.name).dx, lessThan(0));
    expect(_fade(tester) + _fadeFor(tester, SetupStep.name), greaterThan(.5));
    await tester.pump(const Duration(milliseconds: 81));
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(FirstRunDeviceStep), findsOneWidget);
    expect(_fade(tester), inExclusiveRange(0, 1));
    expect(_position(tester).dx, inExclusiveRange(0, .03));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_fade(tester), 1);
    expect(_position(tester), Offset.zero);
    expect(_blocked(tester), isFalse);
  });

  testWidgets('Back reverses the subtle slide and restores the saved name',
      (tester) async {
    await _pump(tester, SetupStep.device);
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_position(tester).dx, lessThan(0));
    expect(_positionFor(tester, SetupStep.device).dx, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 41));
    await tester.pump();
    expect(_position(tester).dx, lessThan(0));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Yuna');
  });

  testWidgets('advancing on a phone keeps outgoing card geometry stable',
      (tester) async {
    await _pump(tester, SetupStep.name, size: const Size(390, 844));
    final card = find
        .ancestor(
            of: find.byType(SetupProgress), matching: find.byType(Container))
        .first;
    final size = tester.getSize(card);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Name saved.'), findsNothing);
    expect(tester.getSize(card), size);
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getSize(card), size);
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion keeps the fade without any translation',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final harness = await _pump(tester, SetupStep.device);
    await _go(tester, harness, SetupStep.network);
    await tester.pump(const Duration(milliseconds: 40));
    expect(_fade(tester), inExclusiveRange(0, 1));
    expect(_position(tester), Offset.zero);
    await tester.pump(const Duration(milliseconds: 41));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(_fade(tester), inExclusiveRange(0, 1));
    expect(_position(tester), Offset.zero);
    await tester.pumpAndSettle();
    expect(_blocked(tester), isFalse);
  });

  testWidgets('a return during exit retargets without remounting the form',
      (tester) async {
    final harness = await _pump(tester, SetupStep.name);
    await tester.enterText(find.byType(TextFormField), 'Unsaved name');
    final form = tester.state(find.byType(TextFormField));
    await _go(tester, harness, SetupStep.device);
    await tester.pump(const Duration(milliseconds: 40));
    final opacity = _fadeFor(tester, SetupStep.name);
    final position = _positionFor(tester, SetupStep.name);
    await _go(tester, harness, SetupStep.name);
    expect(_fade(tester), closeTo(opacity, .0001));
    expect(_position(tester), position);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TextFormField)), same(form));
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Unsaved name');
    expect(find.byType(FirstRunDeviceStep), findsNothing);
    expect(_blocked(tester), isFalse);
  });

  testWidgets('enabling reduce motion during a transition removes the slide',
      (tester) async {
    final harness = await _pump(tester, SetupStep.device);
    await _go(tester, harness, SetupStep.network);
    await tester.pump(const Duration(milliseconds: 30));
    final opacity = _fade(tester);
    expect(_position(tester).dx, isNot(0));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(_position(tester), Offset.zero);
    expect(_fade(tester), closeTo(opacity, .0001));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunNetworkStep), findsOneWidget);
    expect(_blocked(tester), isFalse);
  });

  testWidgets('unmounting during motion disposes its ticker', (tester) async {
    final harness = await _pump(tester, SetupStep.device);
    await _go(tester, harness, SetupStep.network);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid requests reveal only the latest step', (tester) async {
    final harness = await _pump(tester, SetupStep.name);
    await _go(tester, harness, SetupStep.device);
    await tester.pump(const Duration(milliseconds: 20));
    await _go(tester, harness, SetupStep.network);
    await tester.pump(const Duration(milliseconds: 61));
    await tester.pump();
    expect(find.byType(FirstRunNetworkStep), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 40));
    final opacity = _fadeFor(tester, SetupStep.device);
    final position = _positionFor(tester, SetupStep.device);
    await _go(tester, harness, SetupStep.device);
    expect(_fade(tester), closeTo(opacity, .0001));
    expect(_position(tester), position);
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunNetworkStep), findsNothing);
    expect(find.byType(FirstRunDeviceStep), findsOneWidget);
    expect(_blocked(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outgoing controls leave semantics and keyboard traversal',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final harness = await _pump(tester, SetupStep.device);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _go(tester, harness, SetupStep.network);
      expect(find.semantics.byLabel('This is my first device'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.store.profile!.step, SetupStep.network);
      expect(find.byType(FirstRunNetworkStep), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsWidgets);
      expect(_blocked(tester), isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('outgoing Back cannot change the active step', (tester) async {
    final harness = await _pump(tester, SetupStep.device);
    await _go(tester, harness, SetupStep.network);
    final back = find.descendant(
        of: _panel(tester, SetupStep.device), matching: find.text('Back'));
    expect(back, findsOneWidget);
    await tester.tap(back, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(harness.store.profile!.step, SetupStep.network);
    expect(find.byType(FirstRunNetworkStep), findsOneWidget);
  });

  testWidgets('same-step edits, resizing and failed saves do not replay motion',
      (tester) async {
    final harness = await _pump(tester, SetupStep.name);
    await tester.enterText(find.byType(TextFormField), 'Unsaved name');
    await harness.container
        .read(firstRunProfileProvider.notifier)
        .saveName('Stored');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(_fade(tester), 1);
    expect(_blocked(tester), isFalse);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Unsaved name');
    harness.store.writeError = StateError('disk');
    await tapSetup(tester, 'Continue');
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(_fade(tester), 1);
    expect(_blocked(tester), isFalse);
  });

  for (final size in [const Size(1280, 680), const Size(390, 844)]) {
    for (final step in SetupStep.values) {
      testWidgets('$step transition frames render at $size', (tester) async {
        await prepareSetupPreview(tester);
        final harness = await _pump(tester, step, size: size);
        final prefix =
            'setup-content-motion-${step.name}-${size.width.toInt()}';
        await saveSetupPreview(tester, '$prefix-000');
        final action = switch (step) {
          SetupStep.name => 'Continue',
          SetupStep.device => 'This is my first device',
          SetupStep.network => 'Back',
        };
        await tester.ensureVisible(find.text(action));
        await tester.tap(find.text(action));
        await tester.pump();
        await tester.pump();
        expect(harness.store.profile!.step,
            step == SetupStep.device ? SetupStep.network : SetupStep.device);
        var elapsed = 0;
        for (final delta in List.filled(16, 16)) {
          await tester.pump(Duration(milliseconds: delta));
          elapsed += delta;
          await saveSetupPreview(
              tester, '$prefix-${elapsed.toString().padLeft(3, '0')}');
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(_fade(tester), 1);
        expect(_blocked(tester), isFalse);
      });
    }
  }
}

Future<FirstRunHarness> _pump(WidgetTester tester, SetupStep step,
    {Size size = const Size(1280, 680), bool settle = true}) async {
  final harness = FirstRunHarness(
      profile: FirstRunProfile(displayName: 'Yuna', step: step));
  await harness.pump(tester, size: size, settle: settle);
  return harness;
}

Future<void> _go(
    WidgetTester tester, FirstRunHarness harness, SetupStep step) async {
  await harness.container.read(firstRunProfileProvider.notifier).goTo(step);
  await tester.pump();
  await tester.pump();
}

Finder _panel(WidgetTester tester, [SetupStep? step]) {
  final region = find.byKey(const ValueKey('setup-content'));
  final active = tester.widget<SetupStepTransition>(region).step;
  return find.descendant(
      of: region,
      matching: find.byKey(ValueKey(step ?? active), skipOffstage: false),
      skipOffstage: false);
}

Finder _inside(WidgetTester tester, Type type, [SetupStep? step]) =>
    find.descendant(
        of: _panel(tester, step),
        matching: find.byType(type, skipOffstage: false),
        skipOffstage: false);
double _fade(WidgetTester tester) => _fadeFor(tester);
double _fadeFor(WidgetTester tester, [SetupStep? step]) => tester
    .widget<FadeTransition>(_inside(tester, FadeTransition, step).first)
    .opacity
    .value;
Offset _position(WidgetTester tester) => _positionFor(tester);
Offset _positionFor(WidgetTester tester, [SetupStep? step]) => tester
    .widget<SlideTransition>(_inside(tester, SlideTransition, step).first)
    .position
    .value;
bool _blocked(WidgetTester tester) =>
    tester.widget<IgnorePointer>(_inside(tester, IgnorePointer).first).ignoring;
