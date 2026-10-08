import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';

import '../../support/start_menu.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

InviteCreated _invite(String id) => InviteCreated(
    inviteUri: 'mosh://invite?session=$id',
    sessionId: id,
    meshId: 'mesh',
    fingerprint: 'aabbccdd',
    listenAddress: '127.0.0.1:8765');

Finder _uri(String uri) => find.byWidgetPredicate(
    (widget) => widget is SelectableText && widget.data == uri);

Finder _card(String uri) =>
    find.ancestor(of: _uri(uri), matching: find.byType(InviteResult));

void main() {
  testWidgets('Back during Open keeps the start menu after native completion',
      (tester) async {
    final invite = _invite('alice');
    final bridge = ScriptableBridge()..seedPendingInvites([invite]);
    final opened = Completer<SessionSnapshot>();
    bridge.respondNext(BridgeMethod.openSession, opened.future);
    await pumpStartStep(tester, 'Start a private chat', bridge: bridge);
    await tester.ensureVisible(find.text('Open chat'));
    await tester.tap(find.text('Open chat'));
    await tester.pump();
    await tester.ensureVisible(find.text('Back').hitTestable());
    await tester.tap(find.text('Back').hitTestable());
    await tester.pump();
    opened.complete(bridge.conversations.sessions[invite.sessionId]!);
    await tester.pumpAndSettle();
    expect(find.byType(StartMenu), findsOneWidget);
    expect(find.byType(DmScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved invitations survive a fresh flow and replace independently',
      (tester) async {
    final first = _invite('alice');
    final second = _invite('bob');
    final bridge = ScriptableBridge()..seedPendingInvites([first, second]);
    await pumpStartStep(tester, 'Start a private chat', bridge: bridge);
    expect(find.text('Saved invitations'), findsOneWidget);
    expect(find.byType(InviteResult), findsNWidgets(2));
    expect(find.text('Create new invitation'), findsOneWidget);
    final replace = find.descendant(
        of: _card(first.inviteUri), matching: find.text('New link'));
    await tester.ensureVisible(replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    expect(bridge.lastCall(BridgeMethod.replaceInvite)?.args['sessionId'],
        'alice');
    expect(find.byType(InviteResult), findsNWidgets(2));
    expect(_uri(first.inviteUri), findsNothing);
    expect(_uri(second.inviteUri), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.createPendingInvite), 0);
    expect((await bridge.listSessions()).sessions, isEmpty);
  });

  testWidgets('failed replacement retains the original invitation',
      (tester) async {
    final invite = _invite('alice');
    final bridge = ScriptableBridge()
      ..seedPendingInvites([invite])
      ..failNext(BridgeMethod.replaceInvite,
          error: StateError('replace failed'));
    await pumpStartStep(tester, 'Start a private chat', bridge: bridge);
    await tester.ensureVisible(find.text('New link'));
    await tester.tap(find.text('New link'));
    await tester.pumpAndSettle();
    expect(_uri(invite.inviteUri), findsOneWidget);
    expect(find.textContaining('replace failed'), findsOneWidget);
    expect(find.byType(InviteResult), findsOneWidget);
  });

  testWidgets('Open waits for durable native admission before navigation',
      (tester) async {
    final gateway = ScriptableGateway();
    final invite = _invite('alice');
    final bridge = ScriptableBridge(conversations: gateway.conversations)
      ..seedPendingInvites([invite]);
    final opened = Completer<SessionSnapshot>();
    bridge.respondNext(BridgeMethod.openSession, opened.future);
    await pumpStartStep(tester, 'Start a private chat',
        bridge: bridge, gateway: gateway);
    await tester.ensureVisible(find.text('Open chat'));
    await tester.tap(find.text('Open chat'));
    await tester.pump();
    expect(find.byType(ChatCreateStep), findsOneWidget);
    expect(find.byType(DmScreen), findsNothing);
    expect(bridge.countOf(BridgeMethod.openSession), 1);
    opened.complete(gateway.conversations.sessions[invite.sessionId]!);
    await tester.pumpAndSettle();
    expect(find.byType(DmScreen), findsOneWidget);
  });

  testWidgets(
      'leaving during Open never navigates the disposed creation screen',
      (tester) async {
    final invite = _invite('alice');
    final bridge = ScriptableBridge()..seedPendingInvites([invite]);
    final opened = Completer<SessionSnapshot>();
    bridge.respondNext(BridgeMethod.openSession, opened.future);
    final router = await pumpStartStep(tester, 'Start a private chat', bridge: bridge);
    await tester.ensureVisible(find.text('Open chat'));
    await tester.tap(find.text('Open chat'));
    await tester.pump();
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    opened.complete(bridge.conversations.sessions[invite.sessionId]!);
    await tester.pumpAndSettle();
    expect(find.byType(DmScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing DM list notifications refresh native saved invitations',
      (tester) async {
    final invite = _invite('alice');
    final bridge = ScriptableBridge()..seedPendingInvites([invite]);
    await pumpStartStep(tester, 'Start a private chat', bridge: bridge);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatCreateStep)));
    bridge.conversations.pendingInvites.clear();
    bridge.conversations.hiddenSessions.clear();
    await container
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh();
    await tester.pumpAndSettle();
    expect(find.byType(InviteResult), findsNothing);
    expect(find.text('Create invite link'), findsOneWidget);
  });

  testWidgets('long URI remains two visible lines and copies in full',
      (tester) async {
    final uri = 'mosh://invite?${List.filled(300, 'abcdef').join()}';
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final invite = _invite('alice');
    final bridge = ScriptableBridge()
      ..seedPendingInvites([
        InviteCreated(
            inviteUri: uri,
            sessionId: invite.sessionId,
            meshId: invite.meshId,
            fingerprint: invite.fingerprint,
            listenAddress: invite.listenAddress)
      ]);
    await pumpStartStep(tester, 'Start a private chat', bridge: bridge);
    expect(tester.widget<SelectableText>(_uri(uri)).maxLines, 2);
    await tester.ensureVisible(find.text('Copy link'));
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, uri);
  });
}
