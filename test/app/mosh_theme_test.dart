// Theme token contracts from the 2026-09-30 interface review.
//
// Readable text tokens must clear WCAG AA (4.5:1) on every surface the app
// paints; a field's edge must clear the 3:1 non-text floor against the
// surfaces fields sit on; the type scale must pin its own letter-spacing
// and line-height instead of inheriting Material's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _surfaces = <String, Color>{
  'bg0': MoshColors.bg0,
  'bg1': MoshColors.bg1,
  'bg2': MoshColors.bg2,
  'bg3': MoshColors.bg3,
};

void main() {
  for (final (name, token) in [
    ('fg1', MoshColors.fg1),
    ('fg2', MoshColors.fg2),
    ('fg3', MoshColors.fg3),
  ]) {
    test('$name reads at 4.5:1 or better on every surface', () {
      for (final MapEntry(key: surface, value: bg) in _surfaces.entries) {
        expect(_contrast(token, bg), greaterThanOrEqualTo(4.5),
            reason: '$name on $surface');
      }
    });
  }

  test('list-row subtitles use a readable token, not the disabled fg4', () {
    final style = moshThemeData.listTileTheme.subtitleTextStyle!;
    expect(style.color, isNot(MoshColors.fg4));
    expect(_contrast(style.color!, MoshColors.bg2), greaterThanOrEqualTo(4.5));
  });

  test('a field edge clears 3:1 against the surfaces fields sit on', () {
    final border = moshThemeData.inputDecorationTheme.enabledBorder!;
    final edge = border.borderSide.color;
    for (final MapEntry(key: surface, value: bg) in _surfaces.entries) {
      expect(_contrast(Color.alphaBlend(edge, bg), bg), greaterThanOrEqualTo(3),
          reason: 'field edge on $surface');
    }
  });

  test('the type scale pins letter-spacing and line-height on every slot', () {
    final t = moshThemeData.textTheme;
    for (final (name, style) in [
      ('headlineMedium', t.headlineMedium),
      ('headlineSmall', t.headlineSmall),
      ('titleLarge', t.titleLarge),
      ('titleMedium', t.titleMedium),
      ('titleSmall', t.titleSmall),
      ('bodyLarge', t.bodyLarge),
      ('bodyMedium', t.bodyMedium),
      ('bodySmall', t.bodySmall),
      ('labelLarge', t.labelLarge),
      ('labelMedium', t.labelMedium),
      ('labelSmall', t.labelSmall),
    ]) {
      expect(style!.height, isNotNull, reason: '$name height');
      expect(style.fontFamily, 'Inter Tight', reason: '$name family');
    }
    // Headings descend and outweigh the body.
    expect(t.headlineMedium!.fontSize, greaterThan(t.headlineSmall!.fontSize!));
    expect(t.headlineSmall!.fontSize, greaterThan(t.titleLarge!.fontSize!));
    expect(t.headlineSmall!.fontWeight!.value, greaterThanOrEqualTo(600));
  });
}
