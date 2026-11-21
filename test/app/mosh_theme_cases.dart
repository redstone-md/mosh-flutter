// Theme token contracts: the 2026-09-30 interface review and the Foundations
// tokens of the redesign (MOSH-120).
//
// Readable text tokens must clear WCAG AA (4.5:1) on every surface the app
// paints, and so must each role's "on" colour on its fill; a field's edge
// must clear the 3:1 non-text floor against the surfaces fields sit on; the
// type scale must pin its own letter-spacing and line-height instead of
// inheriting Material's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';

import '../support/contrast.dart';

const _surfaces = <String, Color>{
  'surfaceContainerLowest': MoshColors.surfaceContainerLowest,
  'surfaceContainerLow': MoshColors.surfaceContainerLow,
  'surface': MoshColors.surface,
  'surfaceContainer': MoshColors.surfaceContainer,
  'surfaceContainerHigh': MoshColors.surfaceContainerHigh,
  'surfaceContainerHighest': MoshColors.surfaceContainerHighest,
};

/// Text painted on a fill of its own: (name, text, fill).
const _onFill = <(String, Color, Color)>[
  ('onPrimary', MoshColors.onPrimary, MoshColors.primary),
  (
    'onPrimaryContainer',
    MoshColors.onPrimaryContainer,
    MoshColors.primaryContainer
  ),
  ('onSecondary', MoshColors.onSecondary, MoshColors.secondary),
  (
    'onSecondaryContainer',
    MoshColors.onSecondaryContainer,
    MoshColors.secondaryContainer
  ),
  ('onTertiary', MoshColors.onTertiary, MoshColors.tertiary),
  (
    'onTertiaryContainer',
    MoshColors.onTertiaryContainer,
    MoshColors.tertiaryContainer
  ),
  ('onError', MoshColors.onError, MoshColors.error),
  ('onErrorContainer', MoshColors.onErrorContainer, MoshColors.errorContainer),
  (
    'onWarningContainer',
    MoshColors.onWarningContainer,
    MoshColors.warningContainer
  ),
  ('onInverseSurface', MoshColors.onInverseSurface, MoshColors.inverseSurface),
  ('onOutgoing', MoshColors.onOutgoing, MoshColors.outgoing),
  ('onOutgoingVariant', MoshColors.onOutgoingVariant, MoshColors.outgoing),
  ('outgoingError', MoshColors.outgoingError, MoshColors.outgoing),
  ('onAvatar on avatar1', MoshColors.onAvatar, MoshColors.avatar1),
  ('onAvatar on avatar2', MoshColors.onAvatar, MoshColors.avatar2),
  ('onAvatar on avatar3', MoshColors.onAvatar, MoshColors.avatar3),
  ('onAvatar on avatar4', MoshColors.onAvatar, MoshColors.avatar4),
  // Pairs the screens paint across roles.
  ('onPrimary on error', MoshColors.onPrimary, MoshColors.error),
  (
    'onSurface on secondaryContainer',
    MoshColors.onSurface,
    MoshColors.secondaryContainer
  ),
  (
    'onSurfaceVariant on secondaryContainer',
    MoshColors.onSurfaceVariant,
    MoshColors.secondaryContainer
  ),
  (
    'onSurface on outgoingMessage',
    MoshColors.onSurface,
    MoshColors.outgoingMessage
  ),
  (
    'onSurfaceVariant on outgoingMessage',
    MoshColors.onSurfaceVariant,
    MoshColors.outgoingMessage
  ),
  ('error on outgoingMessage', MoshColors.error, MoshColors.outgoingMessage),
  ('error on errorContainer', MoshColors.error, MoshColors.errorContainer),
  (
    'warning on warningContainer',
    MoshColors.warning,
    MoshColors.warningContainer
  ),
  ('info on tertiaryContainer', MoshColors.info, MoshColors.tertiaryContainer),
];

void main() {
  for (final (name, token) in [
    ('onSurface', MoshColors.onSurface),
    ('onSurfaceVariant', MoshColors.onSurfaceVariant),
    ('onSurfaceMuted', MoshColors.onSurfaceMuted),
    ('primary', MoshColors.primary),
    ('error', MoshColors.error),
    ('warning', MoshColors.warning),
    ('tertiary', MoshColors.tertiary),
  ]) {
    test('$name reads at 4.5:1 or better on every surface', () {
      for (final MapEntry(key: surface, value: bg) in _surfaces.entries) {
        expect(contrastRatio(token, bg), greaterThanOrEqualTo(4.5),
            reason: '$name on $surface');
      }
    });
  }

  test('text on a filled role reads at 4.5:1 or better', () {
    for (final (name, text, fill) in _onFill) {
      expect(contrastRatio(text, fill), greaterThanOrEqualTo(4.5),
          reason: name);
    }
  });

  test('the Material colour scheme pairs read at 4.5:1 or better', () {
    final c = moshThemeData.colorScheme;
    for (final (name, text, fill) in [
      ('primary', c.onPrimary, c.primary),
      ('primaryContainer', c.onPrimaryContainer, c.primaryContainer),
      ('secondary', c.onSecondary, c.secondary),
      ('secondaryContainer', c.onSecondaryContainer, c.secondaryContainer),
      ('tertiary', c.onTertiary, c.tertiary),
      ('tertiaryContainer', c.onTertiaryContainer, c.tertiaryContainer),
      ('error', c.onError, c.error),
      ('errorContainer', c.onErrorContainer, c.errorContainer),
      ('surface', c.onSurface, c.surface),
      ('surface variant text', c.onSurfaceVariant, c.surfaceContainerHighest),
      ('inverseSurface', c.onInverseSurface, c.inverseSurface),
      ('inversePrimary', c.inversePrimary, c.inverseSurface),
    ]) {
      expect(contrastRatio(text, fill), greaterThanOrEqualTo(4.5),
          reason: name);
    }
  });

  test('list-row subtitles use a readable token, not the outline colour', () {
    final style = moshThemeData.listTileTheme.subtitleTextStyle!;
    expect(style.color, isNot(MoshColors.outline));
    expect(contrastRatio(style.color!, MoshColors.surfaceContainerHigh),
        greaterThanOrEqualTo(4.5));
  });

  test('a field edge clears 3:1 against the surfaces fields sit on', () {
    final border = moshThemeData.inputDecorationTheme.enabledBorder!;
    final edge = border.borderSide.color;
    for (final MapEntry(key: surface, value: bg) in _surfaces.entries) {
      expect(contrastRatio(Color.alphaBlend(edge, bg), bg),
          greaterThanOrEqualTo(3),
          reason: 'field edge on $surface');
    }
  });

  test('the type scale pins letter-spacing and line-height on every slot', () {
    final t = moshThemeData.textTheme;
    for (final (name, style) in [
      ('displayLarge', t.displayLarge),
      ('displayMedium', t.displayMedium),
      ('displaySmall', t.displaySmall),
      ('headlineLarge', t.headlineLarge),
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
      expect(style.letterSpacing, isNotNull, reason: '$name letter-spacing');
      expect(style.fontFamily, 'Onest', reason: '$name family');
    }
    // Headings descend into the body.
    expect(t.headlineMedium!.fontSize, greaterThan(t.headlineSmall!.fontSize!));
    expect(t.headlineSmall!.fontSize, greaterThan(t.titleLarge!.fontSize!));
    expect(t.titleLarge!.fontSize, greaterThan(t.bodyLarge!.fontSize!));
  });
}
