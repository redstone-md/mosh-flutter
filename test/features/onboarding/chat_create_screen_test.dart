// Widget tests for the ChatCreateScreen (chat-create step, 1-в-1 with the
// React ChatCreateStep). Mirrors the established slice-one pattern:
// ProviderScope override of `bridgeFacadeProvider` with a scripted bridge +
// localized MaterialApp.router (the step's Back button uses context.go).
//
// Test 1: initial state -- Create button reads onboardChatCreate, no
//   InviteResult renders (no lastInvite yet).
// Test 2: tap Create -> inviteFlowProvider.create() runs (the fake returns
//   a known inviteUri), lastInvite is set, the button flips to
//   onboardChatRecreate, and InviteResult renders the URI.
// Test 3: with lastInvite present -> tap Copy -> the URI is written to the
//   clipboard (asserted via the flutter/services clipboard method channel
//   handler) and the button label/icon flips to onboardCopied.
// Test 4: Back button -> context.go(AppRoutes.onboarding); asserted by
//   routing through the real appRouter and expecting the OnboardingScreen
//   to reappear.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/onboarding/chat_create_screen.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/state/gateway_provider.dart'
    show bridgeFacadeProvider, gatewayProvider;
import '../../support/pump.dart';

/// A bridge whose `createInvite` hands back [inviteUri].
ScriptableBridge _bridgeOffering(String inviteUri) => ScriptableBridge()
  ..seedInvite(InviteCreated(
    inviteUri: inviteUri,
    sessionId: 'controlled-1',
    meshId: 'controlled-mesh',
    fingerprint: 'AABBCCDDEEFF0011',
    listenAddress: '127.0.0.1:8765',
  ));

void main() {
  Future<void> pumpCreateStep(
    WidgetTester tester,
    BridgeFacade bridge, {
    String initialLocation = AppRoutes.chatCreate,
  }) =>
      pumpRoute(tester, initialLocation,
          overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
  testWidgets(
      'initial state shows Create button (no lastInvite) and no InviteResult',
      (tester) async {
    await pumpCreateStep(tester, _bridgeOffering('mosh://invite?x=1'));

    expect(find.text('New private chat'), findsOneWidget);
    expect(find.text('Create invite link'), findsOneWidget);
    expect(find.byType(InviteResult), findsNothing);
    // Recreate label is not shown until an invite exists.
    expect(find.text('Replace invite link'), findsNothing);
  });

  testWidgets(
      'tapping Create calls inviteFlowProvider.create() and surfaces the URI',
      (tester) async {
    const uri = 'mosh://invite?mesh=m&session=s#fp=Z';
    final bridge = _bridgeOffering(uri);
    await pumpCreateStep(tester, bridge);

    // Create is a FilledButton; before tap the Recreate label is absent.
    final createButton =
        find.widgetWithText(FilledButton, 'Create invite link');
    expect(createButton, findsOneWidget);

    await tester.tap(createButton);
    await tester.pumpAndSettle();

    // After create resolves: label flips to Recreate, InviteResult renders
    // the controlled URI.
    expect(find.text('Replace invite link'), findsOneWidget);
    expect(find.byType(InviteResult), findsOneWidget);
    expect(find.text(uri), findsOneWidget);
    // Provider initialization plus the explicit post-create refresh.
    expect(bridge.countOf(BridgeMethod.listSessions), 2);
  });

  testWidgets(
      'tapping Copy writes the URI to the clipboard and flips the label',
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

    // First create an invite so InviteResult + Copy button render.
    await tester.tap(find.widgetWithText(FilledButton, 'Create invite link'));
    await tester.pumpAndSettle();

    // Copy button reads "Copy link" before the tap.
    expect(find.text('Copy link'), findsOneWidget);
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();

    // The URI was written to the clipboard and the button flipped.
    expect(copied, uri);
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
  });

  testWidgets('Back button returns to the onboarding menu', (tester) async {
    await pumpCreateStep(tester, _bridgeOffering('mosh://invite?back=1'));

    // The step's Back affordance reads the localized "Back" label.
    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Routing returned to '/' (onboarding): the menu screen reappears.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(ChatCreateScreen), findsNothing);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Create invite link'));
    await tester.pumpAndSettle();

    final l =
        AppLocalizations.of(tester.element(find.byType(ChatCreateScreen)))!;
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

    await tester.tap(find.widgetWithText(FilledButton, 'Create invite link'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.widgetWithText(FilledButton, 'Create invite link'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);

    // Second attempt succeeds -> the error is cleared at the start of the
    // attempt and the InviteResult renders instead.
    await tester.tap(find.widgetWithText(FilledButton, 'Create invite link'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(find.byType(InviteResult), findsOneWidget);
    expect(find.text(uri), findsOneWidget);
  });

  testWidgets('Open chat lands on the DM the invite created', (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    await pumpRoute(tester, AppRoutes.chatCreate, overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      gatewayProvider.overrideWithValue(gateway),
    ]);

    await tester.tap(find.widgetWithText(FilledButton, 'Create invite link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();

    expect(find.byType(DmScreen), findsOneWidget);
    expect(find.byType(ChatCreateScreen), findsNothing);
  });
}
