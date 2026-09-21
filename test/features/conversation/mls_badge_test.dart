// Unit + widget tests for the OpenMLS-protection badge (`MlsBadge`) and
// its placement in the DM sender-meta row. `MlsBadge` lives in
// lib/src/features/conversation/conversation_helpers.dart and is composed
// into the sender meta via `SenderMeta` (extracted from dm_screen.dart to
// keep that screen under the 500-line file-size discipline).
//
// Coverage:
//   1. `MlsBadge` renders the literal acronym "MLS" (not localized).
//   2. `MlsBadge` exposes a `Tooltip` with the `mlsBadgeTooltip` message
//      and a `Semantics` label matching `mlsBadgeLabel`.
//   3. Pumped inside `DmScreen` with one non-grouped peer message, the
//      "MLS" badge renders next to the sender name (both visible).
//   4. Pumped with two peer messages from the same sender 1 minute apart
//      (the second groups under the first), "MLS" renders EXACTLY ONCE --
//      pinning the "badge only on non-grouped rows" behavior (the grouped
//      row omits the whole meta, so its badge is absent).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/state/session_providers.dart';
import '../../support/message_builders.dart';
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

  group('DmScreen sender-meta MLS badge', () {
    const sessionId = 'sess-1';
    final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z

    testWidgets('renders next to the sender name on a non-grouped row',
        (tester) async {
      final snapshot = TestSnapshots.dm(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          TestMessages.dm(fromDevice: 'bob', body: 'first', sentAtMs: base),
        ],
      );

      await pumpScreen(tester, const DmScreen(sessionId: sessionId),
          overrides: [
            activeSessionProvider(sessionId)
                .overrideWith((ref) async => snapshot),
          ]);

      // The sender name renders in a message row (so the badge sits next
      // to it, not alone). Scoped to ConversationMessageRow because the DM AppBar
      // title now also shows the peer name.
      expect(
        find.descendant(
          of: find.byType(ConversationMessageRow),
          matching: find.text('bob'),
        ),
        findsOneWidget,
      );
      // The MLS badge renders in the meta row.
      expect(find.text('MLS'), findsOneWidget);
    });

    testWidgets(
        'renders EXACTLY ONCE when the second message groups under the first',
        (tester) async {
      final snapshot = TestSnapshots.dm(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          TestMessages.dm(fromDevice: 'bob', body: 'first', sentAtMs: base),
          TestMessages.dm(
              fromDevice: 'bob',
              body: 'second',
              sentAtMs: base + BigInt.from(60 * 1000)),
        ],
      );

      await pumpScreen(tester, const DmScreen(sessionId: sessionId),
          overrides: [
            activeSessionProvider(sessionId)
                .overrideWith((ref) async => snapshot),
          ]);

      // Both message bodies render.
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);

      // The sender name renders exactly once in a message row (the
      // grouped row omits its meta). Scoped to ConversationMessageRow because the DM
      // AppBar title now also shows the peer name, so an unscoped
      // find.text('bob') would match the header.
      expect(
        find.descendant(
          of: find.byType(ConversationMessageRow),
          matching: find.text('bob'),
        ),
        findsOneWidget,
      );

      // The MLS badge renders EXACTLY ONCE: the grouped row omits the whole
      // meta, so its badge is absent.
      expect(find.text('MLS'), findsOneWidget);
    });
  });
}
