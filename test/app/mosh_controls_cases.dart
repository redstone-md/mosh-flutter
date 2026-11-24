// Contracts of the control themes (Components page, MOSH-133): on a phone a
// control is a 48 px target, keyboard focus is always drawn, and whatever a
// control says stays readable under its hover and pressed layers and in its
// lit state. They hold for both palettes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_field.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/app/mosh_switch.dart';
import 'package:mosh/src/app/mosh_theme.dart';

import '../support/contrast.dart';

const _states = <(String, Set<WidgetState>)>[
  ('hovered', {WidgetState.hovered}),
  ('pressed', {WidgetState.pressed}),
  ('focused', {WidgetState.focused}),
];

/// The controls a screen is built from, each findable by its type.
Widget _controls(MoshColors colors) => Scaffold(
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        FilledButton(onPressed: () {}, child: const Text('Go')),
        OutlinedButton(onPressed: () {}, child: const Text('Go')),
        TextButton(onPressed: () {}, child: const Text('Go')),
        IconButton(onPressed: () {}, icon: const Icon(MoshIcons.close)),
        IconButton(
            key: const ValueKey('tonal'),
            onPressed: () {},
            style: moshTonalIconButtonStyle(colors),
            icon: const Icon(MoshIcons.close)),
        const MoshField(label: 'Name', child: TextField()),
        MoshSelect<int>(
            label: 'Delay',
            value: 1,
            options: const [MoshSelectOption(1, 'One minute')],
            onChanged: (_) {}),
        Slider(value: 0.4, onChanged: (_) {}),
      ]),
    );

void main() {
  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    group(palette, () => _contracts(colors));
  }

  testWidgets('a field is announced under the label that stands above it',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: buildMoshTheme(),
      home: const Scaffold(
          body: MoshField(label: 'Display name', child: TextField())),
    ));

    expect(find.text('Display name'), findsOneWidget);
    expect(tester.getSemantics(find.byType(TextField)),
        isSemantics(label: 'Display name', isTextField: true));
    semantics.dispose();
  });
}

void _contracts(MoshColors c) {
  for (final (device, platform, height) in [
    ('desktop', TargetPlatform.windows, 40.0),
    ('phone', TargetPlatform.android, 48.0),
  ]) {
    testWidgets('a control is $height px tall on the $device', (tester) async {
      await tester.pumpWidget(
          MaterialApp(theme: buildMoshTheme(c, platform), home: _controls(c)));

      for (final control in [
        find.byType(FilledButton),
        find.byType(OutlinedButton).first,
        find.byType(TextButton),
        find.byType(IconButton).first,
        find.byKey(const ValueKey('tonal')),
        find.byType(TextField),
        find.widgetWithText(OutlinedButton, 'One minute'),
      ]) {
        expect(tester.getSize(control).height, height, reason: '$control');
      }
      // Narrow labels still give a phone a full-width target.
      expect(tester.getSize(find.byType(TextButton)).width,
          greaterThanOrEqualTo(height));
    });
  }

  testWidgets('Tab draws the focus ring around a button', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildMoshTheme(c, TargetPlatform.windows),
        home: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Go')))));
    ShapeBorder shape() => tester
        .widget<Material>(find.descendant(
            of: find.byType(FilledButton), matching: find.byType(Material)))
        .shape!;
    expect((shape() as StadiumBorder).side.style, BorderStyle.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final ring = (shape() as StadiumBorder).side;
    expect(ring.color, c.focusRing);
    expect(ring.width, 2);
    expect(ring.strokeAlign, BorderSide.strokeAlignOutside);
  });

  test('labels stay readable under the hover, pressed and focus layers', () {
    final theme = buildMoshTheme(c);
    for (final (name, style, fill) in [
      ('primary', theme.filledButtonTheme.style!, c.primary),
      ('outlined', theme.outlinedButtonTheme.style!, c.surface),
      ('text', theme.textButtonTheme.style!, c.surfaceContainerHigh),
    ]) {
      for (final (state, states) in _states) {
        final layer = style.overlayColor!.resolve(states)!;
        final ink = style.foregroundColor!.resolve(states)!;
        expect(contrastRatio(ink, Color.alphaBlend(layer, fill)),
            greaterThanOrEqualTo(4.5),
            reason: '$name $state');
      }
      expect(style.overlayColor!.resolve({}), isNull, reason: '$name at rest');
    }
  });

  testWidgets('a switch shows which way it is set in both of its states',
      (tester) async {
    Future<(Color, Color)> drawn(bool value) async {
      await tester.pumpWidget(MaterialApp(
          theme: buildMoshTheme(c),
          home: Scaffold(
              body: MoshSwitchRow(
                  title: 'Read receipts', value: value, onChanged: (_) {}))));
      await tester.pumpAndSettle();
      final parts = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((part) => part.decoration)
          .toList();
      return (
        (parts[0]! as ShapeDecoration).color!,
        (parts[1]! as BoxDecoration).color!
      );
    }

    final (onTrack, onThumb) = await drawn(true);
    final (offTrack, offThumb) = await drawn(false);
    expect(contrastRatio(onThumb, onTrack), greaterThanOrEqualTo(3));
    expect(contrastRatio(offThumb, offTrack), greaterThanOrEqualTo(3));
    // On and off differ by more than the thumb's place.
    expect(onTrack, isNot(offTrack));
  });

  testWidgets('the keyboard reaches a switch row and flips it', (tester) async {
    final semantics = tester.ensureSemantics();
    var value = false;
    await tester.pumpWidget(MaterialApp(
        theme: buildMoshTheme(c, TargetPlatform.windows),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => MoshSwitchRow(
                    title: 'Read receipts',
                    subtitle: 'Let contacts see it',
                    value: value,
                    onChanged: (next) => setState(() => value = next))))));
    expect(
        tester.getSemantics(find.byType(MoshSwitchRow)),
        isSemantics(
            label: 'Read receipts\nLet contacts see it',
            hasToggledState: true,
            isToggled: false,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final ring = tester
        .widgetList<DecoratedBox>(find.descendant(
            of: find.byType(MoshSwitchRow),
            matching: find.byType(DecoratedBox)))
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .map((decoration) => decoration.shape)
        .whereType<RoundedRectangleBorder>()
        .where((shape) => shape.side.color == c.focusRing);
    expect(ring, hasLength(1), reason: 'keyboard focus is drawn');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(value, isTrue);
    semantics.dispose();
  });

  testWidgets('a switch row being saved takes no press', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
        theme: buildMoshTheme(c),
        home: Scaffold(
            body: MoshSwitchRow(
                title: 'Read receipts',
                value: true,
                saving: true,
                onChanged: changes.add))));
    await tester.tap(find.byType(MoshSwitchRow));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(changes, isEmpty);
  });

  test('a lit filter chip reads on its fill, a resting one on the surface', () {
    final theme = buildMoshTheme(c).chipTheme;
    final label = theme.labelStyle!.color! as WidgetStateColor;
    const lit = {WidgetState.selected};
    expect(contrastRatio(label.resolve(lit), theme.color!.resolve(lit)!),
        greaterThanOrEqualTo(4.5));
    expect(
        contrastRatio(label.resolve({}), c.surface), greaterThanOrEqualTo(4.5));
    final edge = theme.side! as WidgetStateBorderSide;
    expect(edge.resolve({WidgetState.focused})!.color, c.focusRing);
  });
}
