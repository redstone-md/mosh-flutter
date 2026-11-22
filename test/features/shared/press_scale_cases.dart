import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/shared/press_scale.dart';

import '../../support/pump.dart';

const _target = Key('press-target');

/// Mounts a 100x100 tappable target under [PressScale].
Future<void> _pump(WidgetTester tester,
        {bool enabled = true, VoidCallback? onTap}) =>
    pumpScreen(
      tester,
      Center(
        child: PressScale(
          enabled: enabled,
          child: GestureDetector(
            key: _target,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

/// The target's painted size, transforms included.
Size _painted(WidgetTester tester) => tester.getRect(find.byKey(_target)).size;

void main() {
  testWidgets('PressScale shrinks while pressed and restores on release',
      (tester) async {
    var tapped = false;
    await _pump(tester, onTap: () => tapped = true);
    expect(_painted(tester), const Size(100, 100));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(_target)));
    await tester.pumpAndSettle();
    expect(_painted(tester).width, moreOrLessEquals(96));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_painted(tester), const Size(100, 100));
    expect(tapped, isTrue);
  });

  testWidgets('a disabled PressScale keeps its size while pressed',
      (tester) async {
    await _pump(tester, enabled: false);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(_target)));
    await tester.pumpAndSettle();
    expect(_painted(tester), const Size(100, 100));
    await gesture.up();
  });
}
