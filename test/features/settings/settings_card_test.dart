// Contracts of the Settings card family (Components page, MOSH-138): the
// card's surface, its padding and row heights per device, and the line that
// opens what a card folds away. They hold for both palettes.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_card.dart';
import 'package:mosh/src/features/settings/settings_nav.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/features/shared/mosh_disclosure.dart';

Future<void> _pump(WidgetTester tester, Widget child,
        {MoshColors colors = MoshColors.dark,
        TargetPlatform platform = TargetPlatform.linux}) =>
    tester.pumpWidget(MaterialApp(
      theme: buildMoshTheme(colors, platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 400, child: child)),
    ));

const _card = SettingsCard(
    icon: MoshIcons.mic,
    title: 'Microphone',
    hint: 'Used for calls and voice messages',
    child: Text('control'));

void main() {
  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    testWidgets('$palette: a card is a panel with a quiet edge',
        (tester) async {
      await _pump(tester, _card, colors: colors);
      final surface = tester.widget<Material>(find
          .descendant(
              of: find.byType(SettingsSurface), matching: find.byType(Material))
          .first);
      expect(surface.color, colors.surfaceContainerLow);
      expect(
          surface.shape,
          RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(28)),
              side: BorderSide(color: colors.outlineVariant)));
      final plate = tester.widget<Container>(find
          .descendant(
              of: find.byType(SettingsIcon), matching: find.byType(Container))
          .first);
      expect((plate.decoration! as BoxDecoration).color,
          colors.surfaceContainerHighest);
      expect(tester.widget<Icon>(find.byIcon(MoshIcons.mic)).color,
          colors.primary);
    });

    testWidgets('$palette: the selected section is lit', (tester) async {
      await _pump(
          tester,
          SettingsNav(
              sidebar: true,
              selected: SettingsSection.devices,
              onSelect: (_) {},
              onExit: () {}),
          colors: colors);
      Material row(String label) => tester.widget(find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first);
      expect(row('Devices').color, colors.secondaryContainer);
      expect(row('Profile').color, Colors.transparent);
      expect(tester.widget<Text>(find.text('Devices')).style!.color,
          colors.onSecondaryContainer);
    });
  }

  for (final (platform, inset, row) in [
    (TargetPlatform.linux, 20.0, 40.0),
    (TargetPlatform.android, 16.0, 48.0),
  ]) {
    testWidgets('$platform: the card pads $inset px, a section row is $row px',
        (tester) async {
      await _pump(tester, _card, platform: platform);
      final card = tester.getTopLeft(find.byType(SettingsSurface));
      expect(tester.getTopLeft(find.byType(SettingsIcon)) - card,
          Offset(inset, inset));

      await _pump(
          tester, SettingsNav(selected: null, onSelect: (_) {}, onExit: () {}),
          platform: platform);
      expect(
          tester
              .getSize(find
                  .ancestor(
                      of: find.text('Devices'), matching: find.byType(InkWell))
                  .first)
              .height,
          row);
    });
  }

  testWidgets(
      'a disclosure builds what it folds on the first opening, keeps its '
      'state when folded, and says whether it is open', (tester) async {
    final semantics = tester.ensureSemantics();
    var builds = 0;
    await _pump(
        tester,
        MoshDisclosure(
            label: 'What is sent',
            child: Builder(builder: (context) {
              builds++;
              return const TextField();
            })));
    expect(builds, 0);
    SemanticsNode line() => tester.getSemantics(find.text('What is sent'));
    expect(line(), isSemantics(isExpanded: false));

    await tester.tap(find.text('What is sent'));
    await tester.pumpAndSettle();
    expect(line(), isSemantics(isExpanded: true));
    await tester.enterText(find.byType(TextField), 'kept');

    await tester.tap(find.text('What is sent'));
    await tester.pumpAndSettle();
    expect(line(), isSemantics(isExpanded: false));
    expect(find.text('kept').hitTestable(), findsNothing);

    await tester.tap(find.text('What is sent'));
    await tester.pumpAndSettle();
    expect(find.text('kept').hitTestable(), findsOneWidget);
    semantics.dispose();
  });
}
