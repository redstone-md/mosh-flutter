import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import '../../support/first_run.dart';
import '../../support/scriptable_device_link.dart';

void main() {
  testWidgets('pending device join blocks independent continuation and Back',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device));
    await harness.pump(tester);
    harness.link.hold(DeviceLinkMethod.joinLink);
    await tapSetup(tester, 'Connect to an existing profile');
    await tester.enterText(find.byType(TextField), 'mosh://device-link/held');
    await tester.ensureVisible(find.byTooltip('Connect'));
    await tester.tap(find.byTooltip('Connect'));
    await tester.pump();

    expect(harness.link.countOf(DeviceLinkMethod.joinLink), 1);
    expect(harness.link.current.phase, DeviceLinkPhase.idle);
    final independent =
        find.widgetWithText(OutlinedButton, 'This is my first device');
    expect(tester.widget<OutlinedButton>(independent).onPressed, isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
            .onPressed,
        isNull);
    expect(harness.store.profile!.step, SetupStep.device);

    harness.link.release(DeviceLinkMethod.joinLink);
    await tester.pumpAndSettle();
    expect(find.text('ABCDEF123456'), findsOneWidget);
    expect(harness.store.profile!.step, SetupStep.device);
  });

  testWidgets(
      'device polling failure retains proof and blocks setup until retry',
      (tester) async {
    final harness = FirstRunHarness(
        profile:
            const FirstRunProfile(displayName: 'Juno', step: SetupStep.device));
    await harness.pump(tester);
    harness.link.failNext(DeviceLinkMethod.snapshot);
    await harness.container.read(deviceLinkProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'This is my first device'))
            .onPressed,
        isNull);
    expect(harness.store.profile!.step, SetupStep.device);
    await tapSetup(tester, 'Retry');
    await tapSetup(tester, 'This is my first device');
    expect(harness.store.profile!.step, SetupStep.network);
  });
}
