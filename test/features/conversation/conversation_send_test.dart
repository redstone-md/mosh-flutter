// Sending, failing, and retrying, over all three conversation kinds.
//
// A send that throws keeps the text in the composer and shows an error
// banner with a Retry button. Submission clears immediately; completion
// preserves a newer draft.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/shared/voice_composer.dart' show VoiceSend;
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/conversation_cases.dart';
import '../../support/pump_route.dart';
import '../../support/scriptable_bridge.dart';
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
  // Regression (CodeAnt PR #197): every voice message left its clip in the
  // app cache.
  testWidgets('a voice clip is gone from the cache once it is sent',
      (tester) async {
    final testCase = conversationCases().first;
    final gateway = ScriptableGateway();
    await pumpConversation(tester, testCase, gateway: gateway);
    final dir = Directory.systemTemp.createTempSync('mosh-voice-sent');
    addTearDown(() => dir.deleteSync(recursive: true));
    final clip = File('${dir.path}/clip.m4a')..writeAsBytesSync([1, 2, 3]);
    final controller = ProviderScope.containerOf(
            tester.element(find.byType(ConversationComposer)))
        .read(conversationControllerProvider(testCase.target).notifier);

    await tester.runAsync(() => controller.sendVoice(VoiceSend(
        path: clip.path,
        mime: 'audio/mp4',
        durationMs: 2000,
        peaksBase64: '')));
    await tester.pumpAndSettle();

    expect(gateway.lastCall(GatewayMethod.sendAttachment), isNotNull);
    expect(clip.existsSync(), isFalse);
  });

  // Regression (CodeAnt PR #6): the router reuses the chat screen between two
  // DMs, so chat A's unsent draft stayed in the composer and went to chat B.
  testWidgets('a draft stays in the chat it was typed in', (tester) async {
    final a = conversationCases(dmId: 'dm-a').first;
    final b = conversationCases(dmId: 'dm-b').first;
    final gateway = ScriptableGateway();
    final router = await pumpRoute(tester, a.route, overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
      a.snapshotOverride(),
      b.snapshotOverride(),
    ]);
    await _type(tester, 'for a only');

    router.go(b.route);
    await tester.pumpAndSettle();
    expect(_composer(tester).text, '');
    await _type(tester, 'for b');
    await _tapSend(tester);
    expect(gateway.argValues<String>(GatewayMethod.send, 'body'), ['for b']);
    expect(gateway.lastCall(GatewayMethod.send)?.target, b.target);

    router.go(a.route);
    await tester.pumpAndSettle();
    expect(_composer(tester).text, 'for a only');
  });

  for (final testCase in conversationCases()) {
    final label = testCase.label;

    testWidgets('$label: a successful retry clears the banner and the composer',
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

      expect(_composer(tester).text, '');

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

      await tester.enterText(_composerField(), 'hello there and more');
      await tester.pump();

      gateway.release(GatewayMethod.send);
      await tester.pumpAndSettle();

      expect(_composer(tester).text, 'hello there and more');
    });
  }
}
