// Protocol badge text/semantics and one badge per multi-party sender block.
// DMs use their header identity and protection details instead of repeating it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import '../../support/conversation_cases.dart';
import '../../support/pump.dart';

void main() {
  group('MlsBadge', () {
    testWidgets('renders the literal "MLS" acronym', (tester) async {
      await pumpScreen(tester, const Scaffold(body: MlsBadge()));
      expect(find.text('MLS'), findsOneWidget);
    });

    testWidgets('exposes the localized tooltip + semantics label',
        (tester) async {
      await pumpScreen(tester, const Scaffold(body: MlsBadge()));

      final l = AppLocalizations.of(tester.element(find.text('MLS')))!;

      // Tooltip carries the localized tooltip message.
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, l.mlsBadgeTooltip);

      // Semantics label mirrors the localized accessibility label.
      expect(find.bySemanticsLabel(l.mlsBadgeLabel), findsOneWidget);
    });
  });

  group('Group sender-meta MLS badge', () {
    final base = BigInt.from(1700000000000);
    for (final count in [1, 2]) {
      testWidgets(
          '$count messages in one sender block show one protection badge',
          (tester) async {
        final testCase = conversationCases()
            .singleWhere((c) => c.target.kind == ConversationKind.group);
        await pumpConversation(tester, testCase, messages: [
          for (var i = 0; i < count; i++)
            TestMessage(
                body: 'message $i', sentAtMs: base + BigInt.from(i * 60000)),
        ]);
        expect(
            find.descendant(
                of: find.byType(ConversationMessageRow),
                matching: find.text('peer')),
            findsOneWidget);
        expect(find.text('MLS'), findsOneWidget);
        for (var i = 0; i < count; i++) {
          expect(find.text('message $i'), findsOneWidget);
        }
      });
    }
  });
}
