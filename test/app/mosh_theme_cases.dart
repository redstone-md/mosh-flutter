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
  'bg0': MoshColors.bg0,
  'bg1': MoshColors.bg1,
  'bg2': MoshColors.bg2,
  'bg3': MoshColors.bg3,
  'surfaceContainerLow': MoshColors.surfaceContainerLow,
  'surfaceContainer': MoshColors.surfaceContainer,
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
  // Pairs the current screens paint through the legacy names.
  ('mossInk on danger', MoshColors.mossInk, MoshColors.danger),
  ('fg1 on mossGlow', MoshColors.fg1, MoshColors.mossGlow),
  ('fg2 on mossGlow', MoshColors.fg2, MoshColors.mossGlow),
  ('fg1 on outgoingMessage', MoshColors.fg1, MoshColors.outgoingMessage),
  ('fg2 on outgoingMessage', MoshColors.fg2, MoshColors.outgoingMessage),
  ('danger on outgoingMessage', MoshColors.danger, MoshColors.outgoingMessage),
  ('danger on dangerSurface', MoshColors.danger, MoshColors.dangerSurface),
  ('warn on warnSurface', MoshColors.warn, MoshColors.warnSurface),
  ('info on channelTint', MoshColors.info, MoshColors.channelTint),
];

void main() {
  for (final (name, token) in [
    ('fg1', MoshColors.fg1),
    ('fg2', MoshColors.fg2),
    ('fg3', MoshColors.fg3),
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

  test('list-row subtitles use a readable token, not the disabled fg4', () {
    final style = moshThemeData.listTileTheme.subtitleTextStyle!;
    expect(style.color, isNot(MoshColors.fg4));
    expect(
        contrastRatio(style.color!, MoshColors.bg2), greaterThanOrEqualTo(4.5));
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
