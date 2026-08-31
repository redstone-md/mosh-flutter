// Widget tests for the mobile conversation search/filter trio ported 1-1
// from React `MobileSearchToggle` / `MobileConversationSearch` /
// `MobileConversationFilterNotice` (ConversationTools.tsx L54-112 +
// ActiveChatHeader.tsx L113-131). Covers: the toggle's open-state tooltip +
// onToggle tap; the search panel's autofocus + the close-button
// clear-then-close call order; the filter notice's null-collapse on
// `all` + its paperclip/label/"All" reset on `attachments` + the reset tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
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
      // Closed -> the search placeholder tooltip (React reuses
      // searchPlaceholder for the non-open aria-label).
      expect(find.byTooltip(l.chatSearchPlaceholder), findsOneWidget);
      expect(find.byTooltip(l.closeMessageSearch), findsNothing);
      await tester.tap(find.byType(MobileSearchToggle));
      expect(tapped, 1);
    });

    testWidgets('open: tooltip = closeMessageSearch, icon tinted primary',
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
      // Open -> the dedicated close tooltip (mirrors React's open-state
      // "Close message search" aria-label).
      expect(find.byTooltip(l.closeMessageSearch), findsOneWidget);
      expect(find.byTooltip(l.chatSearchPlaceholder), findsNothing);
      // The icon is tinted with colorScheme.primary while open (mirrors
      // React's `is-active` class highlight).
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(MobileSearchToggle),
          matching: find.byIcon(Icons.search),
        ),
      );
      expect(icon.color,
          Theme.of(tester.element(find.byType(Scaffold))).colorScheme.primary);
    });

    testWidgets('tapping the toggle fires onToggle', (tester) async {
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
      await tester.tap(find.byType(MobileSearchToggle));
      await tester.pump();
      expect(tapped, 1);
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
      // close button must clear the query before it closes (React L84-87).
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
      // Order matters: clear THEN close (1-1 with React L84-87).
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
      // React returns null; the Flutter port returns a zero-size box that
      // takes no layout space. The notice renders neither the paperclip nor
      // the "All" reset button.
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      // The returned SizedBox.shrink() renders at zero size (mirrors
      // React's `null` taking no layout space in the column).
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
      // Paperclip icon (Icons.attach_file) + the "Files" label + the "All"
      // reset button, 1-1 with React L103-111.
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
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
