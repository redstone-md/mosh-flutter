// Sending, failing, and retrying, over all three conversation kinds.
//
// A send that throws keeps the text in the composer and shows an error
// banner with a Retry button. A send that works clears the composer -- but
// only if it still holds the text that was sent, so anything typed while the
// send was in flight survives.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

Finder _composerField() => find.descendant(
      of: find.byType(ConversationComposer),
      matching: find.byType(TextField),
    );

TextEditingController _composer(WidgetTester tester) =>
    tester.widget<TextField>(_composerField()).controller!;

String _retryLabel(WidgetTester tester) =>
    AppLocalizations.of(tester.element(_composerField()))!.chatErrorRetry;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_composerField(), text);
  await tester.pumpAndSettle();
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.byKey(kComposerSendButtonKey));
  await tester.pumpAndSettle();
}

void main() {
  for (final testCase in conversationCases()) {
    final label = testCase.label;

    testWidgets('$label: a send that throws keeps the text and shows Retry',
        (tester) async {
      final gateway = ScriptableGateway()
        ..failNext(GatewayMethod.send, error: Exception('send boom'));
      await pumpConversation(tester, testCase, gateway: gateway);

      await _type(tester, 'hello there');
      await _tapSend(tester);

      expect(
        gateway.argValues<String>(GatewayMethod.send, 'body'),
        ['hello there'],
      );
      expect(gateway.lastCall(GatewayMethod.send)?.target, testCase.target);
      expect(find.textContaining('send boom'), findsOneWidget);
      expect(find.text(_retryLabel(tester)), findsOneWidget);
      // The text survives, so the user does not have to type it again.
      expect(_composer(tester).text, 'hello there');
    });

    testWidgets('$label: a successful retry clears the banner and the composer',
        (tester) async {
      final gateway = ScriptableGateway()
        ..failNext(GatewayMethod.send, error: Exception('send boom'));
      await pumpConversation(tester, testCase, gateway: gateway);

      await _type(tester, 'hello there');
      await _tapSend(tester);

      final retry = _retryLabel(tester);
      await tester.tap(find.text(retry));
      await tester.pumpAndSettle();

      expect(
        gateway.argValues<String>(GatewayMethod.send, 'body'),
        ['hello there', 'hello there'],
      );
      expect(find.textContaining('send boom'), findsNothing);
      expect(find.text(retry), findsNothing);
      expect(_composer(tester).text, '');
    });

    testWidgets('$label: a successful send clears the composer',
        (tester) async {
      final gateway = ScriptableGateway()..hold(GatewayMethod.send);
      await pumpConversation(tester, testCase, gateway: gateway);

      await _type(tester, 'hello there');
      // Do not settle: the send is still in flight.
      await tester.tap(find.byKey(kComposerSendButtonKey));
      await tester.pump();

      expect(_composer(tester).text, 'hello there');

      gateway.release(GatewayMethod.send);
      await tester.pumpAndSettle();

      expect(_composer(tester).text, '');
    });

    testWidgets('$label: text typed during a send is not overwritten',
        (tester) async {
      final gateway = ScriptableGateway()..hold(GatewayMethod.send);
      await pumpConversation(tester, testCase, gateway: gateway);

      await _type(tester, 'hello there');
      await tester.tap(find.byKey(kComposerSendButtonKey));
      await tester.pump();

      // The field is disabled while the send runs, so write to the
      // controller the way a still-editable field would.
      _composer(tester).text = 'hello there and more';
      await tester.pump();

      gateway.release(GatewayMethod.send);
      await tester.pumpAndSettle();

      expect(_composer(tester).text, 'hello there and more');
    });
  }
}
