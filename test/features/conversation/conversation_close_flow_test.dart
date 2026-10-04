// Leaving a conversation always asks first. The wording follows the kind,
// the behaviour does not: confirm leaves, cancel does nothing.
//
// These use the real router, because a confirmed leave navigates away.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final testCase in conversationCases()) {
    final label = testCase.label;

    testWidgets(
        '$label: confirmed leave drains sends and a failed leave reopens input',
        (tester) async {
      final pending = Completer<void>();
      final gateway = ScriptableGateway()
        ..respondNext(GatewayMethod.send, pending.future)
        ..failNext(GatewayMethod.leave);
      await pumpConversation(tester, testCase,
          gateway: gateway, useRouter: true);
      final field = find.descendant(
          of: find.byType(ConversationComposer),
          matching: find.byType(TextField));
      await tester.enterText(field, 'first');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(field, 'second');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.tap(find.byTooltip('More chat actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(testCase.leaveConfirmLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(testCase.leaveConfirmLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(gateway.countOf(GatewayMethod.leave), 0);
      expect(tester.widget<TextField>(field).enabled, isFalse);

      pending.complete();
      await tester.pumpAndSettle();
      expect(
          gateway.calls
              .where((c) =>
                  c.method == GatewayMethod.send ||
                  c.method == GatewayMethod.leave)
              .map((c) => c.method),
          [GatewayMethod.send, GatewayMethod.send, GatewayMethod.leave]);
      expect(find.byType(testCase.screen.runtimeType), findsOneWidget);
      expect(tester.widget<TextField>(field).enabled, isTrue);
      await tester.enterText(field, 'after failed leave');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
          ['first', 'second', 'after failed leave']);
    });

    testWidgets('$label: the leave button asks before it does anything',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase,
          gateway: gateway, useRouter: true);

      await tester.tap(find.byTooltip('More chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(testCase.leaveConfirmLabel));
      await tester.pumpAndSettle();

      expect(find.text(testCase.leaveTitle), findsOneWidget);
      expect(find.text(testCase.leaveConfirmLabel), findsOneWidget);
      expect(gateway.countOf(GatewayMethod.leave), 0);
    });

    testWidgets('$label: confirming leaves the conversation', (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase,
          gateway: gateway, useRouter: true);

      await tester.tap(find.byTooltip('More chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(testCase.leaveConfirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(testCase.leaveConfirmLabel));
      await tester.pumpAndSettle();

      expect(gateway.lastCall(GatewayMethod.leave)?.target, testCase.target);
    });

    testWidgets('$label: cancelling leaves nothing behind', (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase,
          gateway: gateway, useRouter: true);

      await tester.tap(find.byTooltip('More chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(testCase.leaveConfirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(gateway.countOf(GatewayMethod.leave), 0);
      expect(find.text(testCase.leaveTitle), findsNothing);
      expect(find.byType(testCase.screen.runtimeType), findsOneWidget);
    });
  }
}
