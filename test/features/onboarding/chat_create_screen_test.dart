// Widget tests for the chat-create step (ChatCreateStep), opened the way a
// person does: the start menu in the chat pane at /chat, then a tap on the
// "Start a private chat" card (`pumpStartStep`). The bridge is scripted so
// the invite it hands back is known.
//
// Test 1: initial state -- the Create button reads onboardChatCreate and no
//   InviteResult renders (no lastInvite yet).
// Test 2: tap Create -> inviteFlowProvider.create() runs, InviteResult
//   renders "Invite ready", the URI and the "New link" replace button.
// Test 3: Copy writes the URI to the clipboard (asserted via the
//   flutter/services clipboard method channel), shows the "Copied" toast
//   and flips the button label.
// Test 4: Back returns to the start menu.
// Tests 5-7: a failed create shows a persistent inline error, worded by
//   the bridge error's kind, never a SnackBar, cleared on the next attempt.
// Test 8: Open chat lands on the DM the invite created.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/start_menu.dart';

const _card = 'Start a private chat';

/// A bridge whose `createInvite` hands back [inviteUri].
ScriptableBridge _bridgeOffering(String inviteUri) => ScriptableBridge()
  ..seedInvite(InviteCreated(
    inviteUri: inviteUri,
    sessionId: 'controlled-1',
    meshId: 'controlled-mesh',
    fingerprint: 'AABBCCDDEEFF0011',
    listenAddress: '127.0.0.1:8765',
  ));

final _create = find.widgetWithText(FilledButton, 'Create invite link');

void main() {
  Future<void> pumpCreateStep(WidgetTester tester, BridgeFacade bridge) =>
      pumpStartStep(tester, _card, bridge: bridge);

  Future<void> tapCreate(WidgetTester tester) async {
    await tester.tap(_create);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'initial state shows Create button (no lastInvite) and no InviteResult',
      (tester) async {
    await pumpCreateStep(tester, _bridgeOffering('mosh://invite?x=1'));

    expect(find.byType(ChatCreateStep), findsOneWidget);
    expect(_create, findsOneWidget);
    expect(find.byType(InviteResult), findsNothing);
    // The replace label is not shown until an invite exists.
    expect(find.text('New link'), findsNothing);
  });

  testWidgets(
      'tapping Create calls inviteFlowProvider.create() and surfaces the URI',
      (tester) async {
    const uri = 'mosh://invite?mesh=m&session=s#fp=Z';
    final bridge = _bridgeOffering(uri);
    await pumpCreateStep(tester, bridge);

    await tapCreate(tester);

    // The Create button is replaced by the InviteResult card.
    expect(_create, findsNothing);
    expect(find.byType(InviteResult), findsOneWidget);
    expect(find.text('Invite ready'), findsOneWidget);
    expect(find.text(uri), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'New link'), findsOneWidget);
    expect(find.text('Open chat'), findsOneWidget);
    // Provider initialization plus the explicit post-create refresh.
    expect(bridge.countOf(BridgeMethod.listSessions), 2);
  });

  testWidgets(
      'tapping Copy writes the URI to the clipboard, toasts and flips the label',
      (tester) async {
    const uri = 'mosh://invite?mesh=m&session=copy#fp=Y';
    // Intercept the flutter/services clipboard method channel so the test
    // can assert exactly what Clipboard.setData received.
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
    await pumpCreateStep(tester, _bridgeOffering(uri));
    await tapCreate(tester);

    final copyButton = find.widgetWithText(OutlinedButton, 'Copy link');
    expect(copyButton, findsOneWidget);
    await tester.tap(copyButton);
    await tester.pump();

    // The URI was written to the clipboard; the toast and the flipped
    // button both read "Copied".
    expect(copied, uri);
    expect(find.widgetWithText(OutlinedButton, 'Copied'), findsOneWidget);
    expect(find.text('Copied'), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'Copy link'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('Back returns to the start menu', (tester) async {
    await pumpCreateStep(tester, _bridgeOffering('mosh://invite?back=1'));

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(StartMenu), findsOneWidget);
    expect(find.byType(ChatCreateStep), findsNothing);
  });

  // The bridge throws the generated ConversationBridgeError (ticket 17); the
  // step words the inline error by its kind and never shows the runtime's
  // diagnostic sentence (ticket 18).
  testWidgets('a failed create is worded by the bridge error\'s kind',
      (tester) async {
    const error = ConversationBridgeError(
      kind: ConversationBridgeErrorKind.unavailable,
      message: 'dm runtime unavailable: node down',
    );
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.createInvite, error: error);
    await pumpCreateStep(tester, bridge);

    await tapCreate(tester);

    final l = AppLocalizations.of(tester.element(find.byType(ChatCreateStep)))!;
    expect(find.text(l.chatActionErrorUnavailable), findsOneWidget);
    expect(find.textContaining(error.message), findsNothing);
    expect(find.textContaining('Instance of'), findsNothing);
  });

  testWidgets(
      'a failed create surfaces a persistent inline error (role="alert") and no SnackBar',
      (tester) async {
    const message = 'Invite service offline';
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.createInvite, error: message);
    await pumpCreateStep(tester, bridge);

    await tapCreate(tester);

    // A non-bridge error renders as its own text (the classifier's text
    // arm) and the inline error is the ONE source of feedback -- no
    // transient SnackBar.
    expect(find.text(message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(bridge.countOf(BridgeMethod.listSessions), 0);
  });

  testWidgets('the inline error clears on the next successful create attempt',
      (tester) async {
    const message = 'Invite service offline';
    const uri = 'mosh://invite?mesh=m&session=retry#fp=R';
    await pumpCreateStep(
        tester,
        _bridgeOffering(uri)
          ..failNext(BridgeMethod.createInvite, error: message));

    // First attempt throws -> inline error surfaces.
    await tapCreate(tester);
    expect(find.text(message), findsOneWidget);

    // Second attempt succeeds -> the error is cleared at the start of the
    // attempt and the InviteResult renders instead.
    await tapCreate(tester);
    expect(find.text(message), findsNothing);
    expect(find.byType(InviteResult), findsOneWidget);
    expect(find.text(uri), findsOneWidget);
  });

  testWidgets('Open chat lands on the DM the invite created', (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    await pumpStartStep(tester, _card, bridge: bridge, gateway: gateway);

    await tapCreate(tester);
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();

    expect(find.byType(DmScreen), findsOneWidget);
    expect(find.byType(ChatCreateStep), findsNothing);
  });
}
