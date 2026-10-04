import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

Finder get _field => find.descendant(
      of: find.byType(ConversationComposer),
      matching: find.byType(TextField),
    );

EditableText _editable(WidgetTester tester) => tester.widget<EditableText>(
    find.descendant(of: _field, matching: find.byType(EditableText)));

Future<void> _enter(WidgetTester tester, String body) async {
  tester.testTextInput.enterText(body);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  for (final testCase in conversationCases()) {
    testWidgets(
        '${testCase.label}: Enter keeps focus and admits consecutive sends',
        (tester) async {
      final first = Completer<void>();
      final gateway = ScriptableGateway()
        ..respondNext(GatewayMethod.send, first.future);
      await pumpConversation(tester, testCase, gateway: gateway);
      await tester.tap(_field);
      await tester.pump();

      await _enter(tester, 'first');
      expect(_editable(tester).focusNode.hasFocus, isTrue);
      expect(_editable(tester).controller.text, isEmpty);
      expect(tester.widget<TextField>(_field).enabled, isTrue);
      await _enter(tester, 'second');
      expect(_editable(tester).controller.text, isEmpty);
      expect(gateway.argValues<String>(GatewayMethod.send, 'body'), ['first']);

      first.complete();
      await tester.pumpAndSettle();
      expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
          ['first', 'second']);
      expect(_editable(tester).focusNode.hasFocus, isTrue);
    });

    testWidgets(
        '${testCase.label}: completion preserves an identical new draft',
        (tester) async {
      final first = Completer<void>();
      final gateway = ScriptableGateway()
        ..respondNext(GatewayMethod.send, first.future);
      await pumpConversation(tester, testCase, gateway: gateway);
      await tester.tap(_field);
      await tester.pump();
      await _enter(tester, 'same');
      tester.testTextInput.enterText('same');
      await tester.pump();

      first.complete();
      await tester.pumpAndSettle();
      expect(_editable(tester).controller.text, 'same');
    });

    testWidgets('${testCase.label}: later success preserves an earlier failure',
        (tester) async {
      final first = Completer<void>();
      final gateway = ScriptableGateway()
        ..respondNext(GatewayMethod.send, first.future);
      await pumpConversation(tester, testCase, gateway: gateway);
      await tester.tap(_field);
      await tester.pump();
      await _enter(tester, 'first');
      await _enter(tester, 'second');

      first.completeError(Exception('first failed'));
      await tester.pumpAndSettle();
      expect(find.textContaining('first failed'), findsOneWidget);
      expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
          ['first', 'second']);
      expect(_editable(tester).controller.text, isEmpty);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
          ['first', 'second', 'first']);
      expect(find.textContaining('first failed'), findsNothing);
    });
  }
}
