// Contracts of the Settings card family (Components page, MOSH-138): the
// section that is lit, in both palettes, and the line that opens what a
// card folds away.
import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_switch.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_nav.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/features/settings/settings_toggle_card.dart';
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

void main() {
  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
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

  testWidgets('a switch card ignores a press while its change is being saved',
      (tester) async {
    final pending = Completer<void>();
    final writes = <bool>[];
    await _pump(
        tester,
        SettingsToggleCard(
            key: const PageStorageKey('card'),
            icon: MoshIcons.bug,
            title: 't',
            subtitle: 's',
            detailsTitle: 'What is sent',
            details: 'd',
            read: () async => false,
            write: (value) {
              writes.add(value);
              return pending.future;
            }));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MoshSwitch));
    await tester.pump();
    await tester.tap(find.byType(MoshSwitch));
    await tester.pump();
    expect(writes, [true],
        reason: 'overlapping writes can finish out of order');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the header says the change is still being saved');

    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byType(MoshSwitch));
    await tester.pump();
    expect(writes, [true, false], reason: 'the switch re-enables once done');
  });
}
