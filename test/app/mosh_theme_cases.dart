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

Map<String, Color> _surfaces(MoshColors c) => {
      'surfaceContainerLowest': c.surfaceContainerLowest,
      'surfaceContainerLow': c.surfaceContainerLow,
      'surface': c.surface,
      'surfaceContainer': c.surfaceContainer,
      'surfaceContainerHigh': c.surfaceContainerHigh,
      'surfaceContainerHighest': c.surfaceContainerHighest,
    };

/// Text painted on a fill of its own: (name, text, fill).
List<(String, Color, Color)> _onFill(MoshColors c) => [
      ('onPrimary', c.onPrimary, c.primary),
      ('onPrimaryContainer', c.onPrimaryContainer, c.primaryContainer),
      ('onSecondary', c.onSecondary, c.secondary),
      ('onSecondaryContainer', c.onSecondaryContainer, c.secondaryContainer),
      ('onTertiary', c.onTertiary, c.tertiary),
      ('onTertiaryContainer', c.onTertiaryContainer, c.tertiaryContainer),
      ('onError', c.onError, c.error),
      ('onErrorContainer', c.onErrorContainer, c.errorContainer),
      ('onWarningContainer', c.onWarningContainer, c.warningContainer),
      ('onInverseSurface', c.onInverseSurface, c.inverseSurface),
      ('onOutgoing', c.onOutgoing, c.outgoing),
      ('onOutgoingVariant', c.onOutgoingVariant, c.outgoing),
      ('outgoingError', c.outgoingError, c.outgoing),
      ('onAvatar on avatar1', c.onAvatar, c.avatar1),
      ('onAvatar on avatar2', c.onAvatar, c.avatar2),
      ('onAvatar on avatar3', c.onAvatar, c.avatar3),
      ('onAvatar on avatar4', c.onAvatar, c.avatar4),
      // Pairs the screens paint across roles.
      ('onPrimary on error', c.onPrimary, c.error),
      ('onSurface on secondaryContainer', c.onSurface, c.secondaryContainer),
      (
        'onSurfaceVariant on secondaryContainer',
        c.onSurfaceVariant,
        c.secondaryContainer
      ),
      ('onSurface on outgoingMessage', c.onSurface, c.outgoingMessage),
      (
        'onSurfaceVariant on outgoingMessage',
        c.onSurfaceVariant,
        c.outgoingMessage
      ),
      ('error on outgoingMessage', c.error, c.outgoingMessage),
      ('error on errorContainer', c.error, c.errorContainer),
      ('warning on warningContainer', c.warning, c.warningContainer),
      ('info on tertiaryContainer', c.info, c.tertiaryContainer),
    ];

void main() {
  group('dark', () => _contracts(MoshColors.dark, Brightness.dark));
  group('light', () => _contracts(MoshColors.light, Brightness.light));

  test('a theme change fades each token from one palette to the other', () {
    const from = MoshColors.dark, to = MoshColors.light;
    final half = from.lerp(to, 0.5);
    expect(from.lerp(to, 0).surface, from.surface);
    expect(from.lerp(to, 1).onAvatar, to.onAvatar);
    expect(half.primary, Color.lerp(from.primary, to.primary, 0.5));
    expect(half.outgoing, Color.lerp(from.outgoing, to.outgoing, 0.5));
  });
}

/// The contracts every palette keeps.
void _contracts(MoshColors c, Brightness expected) {
  final surfaces = _surfaces(c);
  final theme = buildMoshTheme(c);

  testWidgets('widgets under the theme read its palette and brightness',
      (tester) async {
    late MoshColors seen;
    late Brightness brightness;
    await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (context) {
          seen = MoshColors.of(context);
          brightness = Theme.of(context).colorScheme.brightness;
          return const SizedBox();
        })));
    expect(seen, same(c));
    expect(brightness, expected);
  });

  for (final (name, token) in [
    ('onSurface', c.onSurface),
    ('onSurfaceVariant', c.onSurfaceVariant),
    ('onSurfaceMuted', c.onSurfaceMuted),
    ('primary', c.primary),
    ('error', c.error),
    ('warning', c.warning),
    ('tertiary', c.tertiary),
  ]) {
    test('$name reads at 4.5:1 or better on every surface', () {
      for (final MapEntry(key: surface, value: bg) in surfaces.entries) {
        expect(contrastRatio(token, bg), greaterThanOrEqualTo(4.5),
            reason: '$name on $surface');
      }
    });
  }

  test('the success mark clears the 3:1 non-text floor on every surface', () {
    for (final MapEntry(key: surface, value: bg) in surfaces.entries) {
      expect(contrastRatio(c.success, bg), greaterThanOrEqualTo(3),
          reason: 'success on $surface');
    }
  });

  test('text on a filled role reads at 4.5:1 or better', () {
    for (final (name, text, fill) in _onFill(c)) {
      expect(contrastRatio(text, fill), greaterThanOrEqualTo(4.5),
          reason: name);
    }
  });

  test('the Material colour scheme pairs read at 4.5:1 or better', () {
    final c = theme.colorScheme;
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
    final style = theme.listTileTheme.subtitleTextStyle!;
    expect(style.color, isNot(c.outline));
    expect(contrastRatio(style.color!, c.surfaceContainerHigh),
        greaterThanOrEqualTo(4.5));
  });

  test('a field edge clears 3:1 against the surfaces fields sit on', () {
    final border = theme.inputDecorationTheme.enabledBorder!;
    final edge = border.borderSide.color;
    for (final MapEntry(key: surface, value: bg) in surfaces.entries) {
      expect(contrastRatio(Color.alphaBlend(edge, bg), bg),
          greaterThanOrEqualTo(3),
          reason: 'field edge on $surface');
    }
  });

  test('the type scale pins letter-spacing and line-height on every slot', () {
    final t = theme.textTheme;
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
