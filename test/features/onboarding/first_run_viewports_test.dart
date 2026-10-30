import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../../support/first_run.dart';
import '../../support/first_run_preview.dart';

// One representative per sizing branch, including short landscape and large text.
const _viewports = [
  (Size(320, 568), 2.0),
  (Size(568, 320), 2.0),
  (Size(768, 1024), 2.0),
  (Size(800, 450), 1.0),
  (Size(1920, 1080), 2.0),
  (Size(1920, 1080), 1.0),
];

const _actions = {
  SetupStep.name: 'Продолжить',
  SetupStep.device: 'Это моё первое устройство',
  SetupStep.network: 'Сохранить и завершить',
};

void main() {
  for (final (size, scale) in _viewports) {
    for (final step in SetupStep.values) {
      testWidgets('$step remains usable at $size with text scale $scale',
          (tester) async {
        await prepareSetupPreview(tester);
        final harness = FirstRunHarness(
            profile: FirstRunProfile(displayName: 'Лена', step: step));
        await harness.pump(tester, size: size, scale: scale);
        await harness.container
            .read(localeProvider.notifier)
            .setLocale(const Locale('ru'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveSetupPreview(tester,
            'first-run-${step.name}-${size.width.toInt()}x${size.height.toInt()}-$scale');
        final action = find.text(_actions[step]!);
        await tester.ensureVisible(action);
        final button = tester.getRect(find.ancestor(
            of: action,
            matching: find
                .byWidgetPredicate((widget) => widget is ButtonStyleButton)));
        expect(button.height, greaterThanOrEqualTo(48));
        expect(button.left, greaterThanOrEqualTo(12));
        expect(button.right, lessThanOrEqualTo(size.width - 12));
        expect(button.top, greaterThanOrEqualTo(44));
        expect(button.bottom, lessThanOrEqualTo(size.height));
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (step == SetupStep.network) {
          expect(find.byType(SessionsScreen), findsOneWidget);
        } else {
          expect(harness.store.profile!.step,
              step == SetupStep.name ? SetupStep.device : SetupStep.network);
        }
      });
    }
  }
}
