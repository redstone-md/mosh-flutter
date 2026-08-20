// Widget tests for the Gap-1 failed-send retry queue in the DM screen
// (lib/src/features/dm/dm_screen.dart): a text send that THROWS records
// `_lastFailedSend` + `_chatError` (the inline ChatError banner appears
// with a Retry button) and LEAVES the composer text intact so the user's
// body survives; a successful retry (the Gateway send succeeds on the
// second call) clears both fields + the composer. 1-1 with React
// `use-chat-orchestration.ts` L85-149 (lastFailedSend / sendMessageBody /
// retryFailedSend / canRetrySend) and private-dm-screen.tsx L337-341
// (the `<ChatError>` banner).
//
// The test gateway is scripted to fail the first `send` and let the
// second one through.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

SessionSnapshot _snapshot({required String sessionId}) => SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: 'peer',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: 'fp-me-1234',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

Future<void> _pump(
  WidgetTester tester,
  ScriptableGateway gateway, {
  required String sessionId,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      activeSessionProvider(sessionId)
          .overrideWith((ref) async => _snapshot(sessionId: sessionId)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DmScreen(sessionId: sessionId),
    ),
  ));
  await tester.pumpAndSettle();
}

// The composer's TextField, scoped under [ConversationComposer] so it does
// not collide with ConversationTools' search TextField (also a TextField).
Finder _composerField() => find.descendant(
      of: find.byType(ConversationComposer),
      matching: find.byType(TextField),
    );

void main() {
  const sessionId = 'sess-failed-send';

  testWidgets(
      'a thrown text send records the failure + banner + keeps the composer body',
      (tester) async {
    final gateway = ScriptableGateway()..failNext(GatewayMethod.send, error: Exception('send boom'));
    await _pump(tester, gateway, sessionId: sessionId);

    // Type a body into the composer and tap Send.
    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    await tester.pumpAndSettle();

    // The Gateway send was attempted once with the body.
    expect(gateway.argValues<String>(GatewayMethod.send, 'body'), ['hello there']);

    // The inline ChatError banner appears (Gap 3) with the error text.
    expect(find.textContaining('send boom'), findsOneWidget);
    // The Retry button (localized) is present because canRetrySend is true.
    final l = AppLocalizations.of(tester.element(find.byType(DmScreen)))!;
    expect(find.text(l.chatErrorRetry), findsOneWidget);

    // The composer body is PRESERVED on failure (not cleared) -- the user's
    // text survives, matching React (composer keeps the body on failure).
    expect(_composerField(), findsOneWidget);
    final controller = tester.widget<TextField>(_composerField());
    expect(controller.controller!.text, 'hello there');
  });

  testWidgets('a successful retry clears the failure + banner + composer',
      (tester) async {
    final gateway = ScriptableGateway()..failNext(GatewayMethod.send, error: Exception('send boom'));
    await _pump(tester, gateway, sessionId: sessionId);

    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    await tester.pumpAndSettle();

    // Banner + Retry are present after the failed first send.
    final l = AppLocalizations.of(tester.element(find.byType(DmScreen)))!;
    expect(find.textContaining('send boom'), findsOneWidget);
    expect(find.text(l.chatErrorRetry), findsOneWidget);

    // Tap Retry -> the second send succeeds, clearing the failure.
    await tester.tap(find.text(l.chatErrorRetry));
    await tester.pumpAndSettle();

    // The Gateway saw two sends (the failed body, then the retry body).
    expect(gateway.argValues<String>(GatewayMethod.send, 'body'), ['hello there', 'hello there']);

    // The banner + Retry are gone after a successful retry.
    expect(find.textContaining('send boom'), findsNothing);
    expect(find.text(l.chatErrorRetry), findsNothing);

    // The composer is cleared after a successful send.
    final controller = tester.widget<TextField>(_composerField());
    expect(controller.controller!.text, '');
  });
}
