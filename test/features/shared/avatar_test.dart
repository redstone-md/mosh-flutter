// The initials avatar is static text, so it reads in text ink on its plate
// rather than in the moss accent reserved for interactive/primary marks,
// and it sits on the type scale.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/avatar.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  testWidgets('initials are non-accent text at 4.5:1 on the plate, 11.5px',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: moshThemeData,
      home: const Scaffold(body: Center(child: Avatar(name: 'Alice Brown'))),
    ));

    final style =
        tester.renderObject<RenderParagraph>(find.text('AB')).text.style!;
    final plate = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(style.color, isNot(moshThemeData.colorScheme.primary));
    expect(_contrast(style.color!, plate.backgroundColor!),
        greaterThanOrEqualTo(4.5));
    expect(style.fontSize, moshThemeData.textTheme.labelMedium!.fontSize);
  });
}
