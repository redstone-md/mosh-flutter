// IVO-12: the gear's press ink froze under the settings route and finished
// fading only after Back, so the button flashed its pressed colour on return.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/settings.dart';

/// The ink still painted on the Material under [button].
List<Object?> _ink(WidgetTester tester, Type button) {
  final ink = Material.of(tester.element(find.descendant(
      of: find.byType(button), matching: find.byType(InkWell))));
  return (ink as dynamic).debugInkFeatures as List<Object?>? ?? const [];
}

Future<void> _pumpRail(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpRoute(tester, AppRoutes.sessions, overrides: [
    ...settingsAudioOverrides(),
    gatewayProvider.overrideWithValue(ScriptableGateway()),
  ]);
}

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('returning from settings shows the gear at rest ($kind)',
        (tester) async {
      await _pumpRail(tester, const Size(1200, 850));
      await tester.tap(find.byType(RailSettingsButton), kind: kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to chats'), kind: kind);
      await tester.pump();
      expect(_ink(tester, RailSettingsButton), isEmpty);
    });
  }

  testWidgets('returning to the phone rail shows its buttons at rest',
      (tester) async {
    await _pumpRail(tester, const Size(390, 844));
    await tester.tap(find.byType(RailNewButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(_ink(tester, RailNewButton), isEmpty);
  });

  testWidgets('keyboard focus stays on the gear after settings',
      (tester) async {
    await _pumpRail(tester, const Size(1200, 850));
    Focus.of(tester.element(find.descendant(
            of: find.byType(RailSettingsButton),
            matching: find.byType(FocusRing))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to chats'));
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
        find.descendant(
            of: find.byType(RailSettingsButton),
            matching: find.byWidget(focused!.widget)),
        findsOneWidget);
  });
}
