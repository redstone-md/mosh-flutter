import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_link_import_form.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../../support/first_run.dart';
import '../../support/first_run_preview.dart';
import '../../support/scriptable_device_link.dart';

const _titles = {
  SetupStep.name: 'Как вас называть?',
  SetupStep.device: 'Настройте это устройство',
  SetupStep.network: 'Настройте подключение',
};

void main() {
  for (final step in SetupStep.values) {
    testWidgets('$step leads with one task heading on a phone', (tester) async {
      await prepareSetupPreview(tester);
      await _pump(tester, step, const Size(390, 844));
      final title = find.text(_titles[step]!);
      expect(title, findsOneWidget);
      // The step leads with its own heading; the device step's link card
      // has one more under it.
      expect(
          find.ancestor(
              of: title,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Semantics && widget.properties.header == true)),
          findsOneWidget);
      await saveSetupPreview(tester, 'first-run-hierarchy-${step.name}-phone');
    });

    testWidgets('$step exposes readable, labeled touch controls',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(tester, step, const Size(390, 844));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('one primary button moves on; reading a QR is the quiet choice',
      (tester) async {
    await _pump(tester, SetupStep.device, const Size(1280, 680));
    expect(find.widgetWithText(FilledButton, 'Это моё первое устройство'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Выбрать картинку с QR'),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Назад'), findsOneWidget);
  });

  testWidgets('a small progress indicator labels only the current step',
      (tester) async {
    await _pump(tester, SetupStep.device, const Size(320, 568));
    expect(find.text('Устройство'), findsOneWidget);
    expect(find.text('Имя'), findsNothing);
    expect(find.text('Сеть'), findsNothing);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();
    expect(find.text('Устройство'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a linked device offers one primary continue action',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Лена', step: SetupStep.device),
        link: ScriptableDeviceLink(
            snapshot: setupDeviceSnapshot(
                phase: DeviceLinkPhase.linked, canJoin: false, devices: 2)));
    await harness.pump(tester);
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.step, SetupStep.network);
  });

  testWidgets('resizing keeps the open importer and unsaved private link',
      (tester) async {
    await prepareSetupPreview(tester);
    await _pump(tester, SetupStep.device, const Size(1280, 680));
    const link = 'mosh://device-link?invite=pending';
    await tester.enterText(find.byType(TextField), link);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceLinkImportForm), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        link);
    await tester.ensureVisible(find.byType(TextField));
    expect(tester.takeException(), isNull);
    await saveSetupPreview(tester, 'first-run-device-import-small');
    tester.view.physicalSize = const Size(1280, 680);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        link);
  });

  testWidgets(
      'a failed name save remains readable and retryable with large text',
      (tester) async {
    await prepareSetupPreview(tester);
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester, size: const Size(320, 568), scale: 2);
    harness.store.writeError = StateError('disk');
    await tester.enterText(find.byType(TextFormField), 'Anna Ivanova');
    await tapSetup(tester, 'Continue');
    expect(find.textContaining('Could not save'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Could not save'));
    expect(tester.takeException(), isNull);
    await saveSetupPreview(tester, 'first-run-name-error-large-text');
    harness.store.writeError = null;
    await tapSetup(tester, 'Continue');
    expect(harness.store.profile!.displayName, 'Anna Ivanova');
    expect(harness.store.profile!.step, SetupStep.device);
  });
}

Future<FirstRunHarness> _pump(
    WidgetTester tester, SetupStep step, Size size) async {
  final harness = FirstRunHarness(
      profile: FirstRunProfile(displayName: 'Лена', step: step));
  await harness.pump(tester, size: size);
  await harness.container
      .read(localeProvider.notifier)
      .setLocale(const Locale('ru'));
  await tester.pumpAndSettle();
  return harness;
}
