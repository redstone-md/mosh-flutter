// Widget tests for the mobile conversation search/filter trio:
// `MobileSearchToggle` / `MobileConversationSearch` /
// `MobileConversationFilterNotice`. Covers: the toggle's open-state tooltip +
// onToggle tap; the search panel's autofocus + the close-button
// clear-then-close call order; the filter notice's null-collapse on
// `all` + its paperclip/label/"All" reset on `attachments` + the reset tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import '../../support/pump.dart';

// Pumps [child] in a localized MaterialApp so the trio's [AppLocalizations]
// resolves (en). The mobile trio does not need a ProviderScope -- it is pure
// presentation with no Riverpod reads.
Future<void> _pump(WidgetTester tester, Widget child) =>
    pumpScreen(tester, Scaffold(body: child));

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

void main() {
  group('MobileSearchToggle', () {
    testWidgets('closed: tooltip = chatSearchPlaceholder, tap fires onToggle',
        (tester) async {
      var tapped = 0;
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileSearchToggle(
                  open: false,
                  onToggle: () => tapped++,
                  l: AppLocalizations.of(context)!,
                )),
      );
      final l = _l(tester);
      // Closed -> the search placeholder tooltip.
      expect(find.byTooltip(l.chatSearchPlaceholder), findsOneWidget);
      expect(find.byTooltip(l.closeMessageSearch), findsNothing);
      await tester.tap(find.byType(MobileSearchToggle));
      expect(tapped, 1);
    });

    testWidgets('open: tooltip = closeMessageSearch, the button on a plate',
        (tester) async {
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileSearchToggle(
                  open: true,
                  onToggle: () {},
                  l: AppLocalizations.of(context)!,
                )),
      );
      final l = _l(tester);
      // Open -> the dedicated close tooltip.
      expect(find.byTooltip(l.closeMessageSearch), findsOneWidget);
      expect(find.byTooltip(l.chatSearchPlaceholder), findsNothing);
      // While its panel is open the button is the tonal icon button.
      final plate = tester.widget<Material>(find
          .descendant(
              of: find.byType(MobileSearchToggle),
              matching: find.byType(Material))
          .first);
      expect(plate.color, MoshColors.dark.surfaceContainerHighest);
    });
  });

  group('MobileConversationSearch', () {
    testWidgets('autofocuses its TextField on mount', (tester) async {
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileConversationSearch(
                  search: '',
                  onSearch: (_) {},
                  onClose: () {},
                  l: AppLocalizations.of(context)!,
                )),
      );
      // The FocusNode created in initState is requested on mount; after
      // pump the TextField's focus node has the primary focus.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('close button calls onSearch("") THEN onClose (order)',
        (tester) async {
      // Record every call into one list so the ORDER is observable -- the
      // close button must clear the query before it closes.
      final calls = <String>[];
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileConversationSearch(
                  search: 'abc',
                  onSearch: (v) => calls.add('search:$v'),
                  onClose: () => calls.add('close'),
                  l: AppLocalizations.of(context)!,
                )),
      );
      final l = _l(tester);
      // The close IconButton carries the closeMessageSearch tooltip.
      await tester.tap(find.byTooltip(l.closeMessageSearch));
      await tester.pump();
      // Order matters: clear THEN close.
      expect(calls, equals(['search:', 'close']));
    });

    testWidgets('onChanged forwards typed text to onSearch', (tester) async {
      String? captured;
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileConversationSearch(
                  search: '',
                  onSearch: (v) => captured = v,
                  onClose: () {},
                  l: AppLocalizations.of(context)!,
                )),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(captured, 'hello');
    });
  });

  group('MobileConversationFilterNotice', () {
    testWidgets('filter == all returns a zero-size SizedBox.shrink',
        (tester) async {
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileConversationFilterNotice(
                  filter: ConversationFilter.all,
                  onFilter: (_) {},
                  l: AppLocalizations.of(context)!,
                )),
      );
      // The notice collapses to a zero-size box that takes no layout space,
      // rendering neither the paperclip nor the "All" reset button.
      expect(find.byIcon(MoshIcons.attach), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      // The returned SizedBox.shrink() renders at zero size.
      final size = tester.getSize(find.byType(MobileConversationFilterNotice));
      expect(size, Size.zero);
    });

    testWidgets('filter == attachments renders paperclip + label + "All"',
        (tester) async {
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileConversationFilterNotice(
                  filter: ConversationFilter.attachments,
                  onFilter: (_) {},
                  l: AppLocalizations.of(context)!,
                )),
      );
      final l = _l(tester);
      // Paperclip icon (MoshIcons.attach) + the "Files" label + the "All"
      // reset button.
      expect(find.byIcon(MoshIcons.attach), findsOneWidget);
      expect(find.text(l.chatFilterAttachments), findsOneWidget);
      expect(find.text(l.chatFilterAll), findsOneWidget);
    });

    testWidgets('tapping "All" fires onFilter(ConversationFilter.all)',
        (tester) async {
      ConversationFilter? captured;
      await _pump(
        tester,
        Builder(
            builder: (context) => MobileConversationFilterNotice(
                  filter: ConversationFilter.attachments,
                  onFilter: (f) => captured = f,
                  l: AppLocalizations.of(context)!,
                )),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(captured, ConversationFilter.all);
    });
  });
}
