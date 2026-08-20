// Widget tests for the Gap-1 failed-send retry queue in the GROUP screen
// (lib/src/features/group/group_screen.dart): a text send that THROWS
// records `_lastFailedSend` + `_chatError` (the inline ChatError banner
// appears with a Retry button) and LEAVES the composer text intact; a
// successful retry clears both + the composer. 1-1 with React
// `use-chat-orchestration.ts` L85-149. Mirrors the DM/channel suites on
// the group send seam.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/pump.dart';

GroupSnapshot _snapshot({required String groupId}) => GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      label: null,
      displayName: 'me',
      deviceFingerprint: 'fp-me',
      creatorFingerprint: 'fp-me',
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(2),
      inviteUri: null,
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

Future<void> _pump(
  WidgetTester tester,
  ScriptableGateway gateway, {
  required String groupId,
}) =>
    pumpScreen(tester, GroupScreen(groupId: groupId), overrides: [
      gatewayProvider.overrideWithValue(gateway),
      groupSnapshotProvider(groupId)
          .overrideWith((ref) async => _snapshot(groupId: groupId)),
    ]);

// The composer's TextField, scoped under [ConversationComposer] so it does
// not collide with ConversationTools' search TextField (also a TextField).
Finder _composerField() => find.descendant(
      of: find.byType(ConversationComposer),
      matching: find.byType(TextField),
    );

void main() {
  const groupId = 'group-failed-send';

  testWidgets(
      'a thrown text send records the failure + banner + keeps the composer body',
      (tester) async {
    final gateway = ScriptableGateway()
      ..failNext(GatewayMethod.send, error: Exception('send boom'));
    await _pump(tester, gateway, groupId: groupId);

    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    await tester.pumpAndSettle();

    expect(
        gateway.argValues<String>(GatewayMethod.send, 'body'), ['hello there']);
    expect(find.textContaining('send boom'), findsOneWidget);
    final l = AppLocalizations.of(tester.element(find.byType(GroupScreen)))!;
    expect(find.text(l.chatErrorRetry), findsOneWidget);

    // The composer body is PRESERVED on failure.
    final controller = tester.widget<TextField>(_composerField());
    expect(controller.controller!.text, 'hello there');
  });

  testWidgets('a successful retry clears the failure + banner + composer',
      (tester) async {
    final gateway = ScriptableGateway()
      ..failNext(GatewayMethod.send, error: Exception('send boom'));
    await _pump(tester, gateway, groupId: groupId);

    await tester.enterText(_composerField(), 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kComposerSendButtonKey));
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(tester.element(find.byType(GroupScreen)))!;
    expect(find.textContaining('send boom'), findsOneWidget);
    expect(find.text(l.chatErrorRetry), findsOneWidget);

    await tester.tap(find.text(l.chatErrorRetry));
    await tester.pumpAndSettle();

    expect(gateway.argValues<String>(GatewayMethod.send, 'body'),
        ['hello there', 'hello there']);
    expect(find.textContaining('send boom'), findsNothing);
    expect(find.text(l.chatErrorRetry), findsNothing);

    final controller = tester.widget<TextField>(_composerField());
    expect(controller.controller!.text, '');
  });
}
