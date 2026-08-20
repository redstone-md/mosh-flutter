// Leaving a conversation always asks first. The wording follows the kind,
// the behaviour does not: confirm leaves, cancel does nothing.
//
// These use the real router, because a confirmed leave navigates away.
import 'package:flutter_test/flutter_test.dart';

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final testCase in conversationCases()) {
    final label = testCase.label;

    testWidgets('$label: the leave button asks before it does anything',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase,
          gateway: gateway, useRouter: true);

      await tester.tap(find.byIcon(testCase.leaveIcon));
      await tester.pumpAndSettle();

      expect(find.text(testCase.leaveTitle), findsOneWidget);
      expect(find.text(testCase.leaveConfirmLabel), findsOneWidget);
      expect(gateway.countOf(GatewayMethod.leave), 0);
    });

    testWidgets('$label: confirming leaves the conversation', (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase,
          gateway: gateway, useRouter: true);

      await tester.tap(find.byIcon(testCase.leaveIcon));
      await tester.pumpAndSettle();
      await tester.tap(find.text(testCase.leaveConfirmLabel));
      await tester.pumpAndSettle();

      expect(gateway.lastCall(GatewayMethod.leave)?.target, testCase.target);
    });

    testWidgets('$label: cancelling leaves nothing behind', (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase,
          gateway: gateway, useRouter: true);

      await tester.tap(find.byIcon(testCase.leaveIcon));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(gateway.countOf(GatewayMethod.leave), 0);
      expect(find.text(testCase.leaveTitle), findsNothing);
      expect(find.byType(testCase.screen.runtimeType), findsOneWidget);
    });
  }
}
