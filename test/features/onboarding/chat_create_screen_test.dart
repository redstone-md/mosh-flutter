// Widget tests for the ChatCreateScreen (chat-create step, 1-в-1 with the
// React ChatCreateStep). Mirrors the established slice-one pattern:
// ProviderScope override of `gatewayProvider` with a controllable fake +
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_screen.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// A FakeGateway subclass whose `createInvite` returns a fixed
/// `InviteCreated` so the step's URI is deterministic. The listenPort +
/// displayName flow through from inviteFlowProvider (the default state).
class _ControlledCreateGateway extends FakeGateway {
  _ControlledCreateGateway(this._inviteUri);

  final String _inviteUri;

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) {
    return Future.value(InviteCreated(
      inviteUri: _inviteUri,
      sessionId: 'controlled-1',
      meshId: 'controlled-mesh',
      fingerprint: 'AABBCCDDEEFF0011',
      listenAddress: '127.0.0.1:${request.listenPort}',
    ));
  }
}

void main() {
  Future<GoRouter> pumpScreen(
    WidgetTester tester,
    Gateway gateway, {
    String initialLocation = AppRoutes.chatCreate,
  }) async {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: appRouter.configuration.routes,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [gatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets(
      'initial state shows Create button (no lastInvite) and no InviteResult',
      (tester) async {
    await pumpScreen(tester, _ControlledCreateGateway('mosh://invite?x=1'));

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
    await pumpScreen(tester, _ControlledCreateGateway(uri));

    // Create is a FilledButton; before tap the Recreate label is absent.
    final createButton = find.widgetWithText(FilledButton, 'Create invite link');
    expect(createButton, findsOneWidget);

    await tester.tap(createButton);
    await tester.pumpAndSettle();

    // After create resolves: label flips to Recreate, InviteResult renders
    // the controlled URI.
    expect(find.text('Replace invite link'), findsOneWidget);
    expect(find.byType(InviteResult), findsOneWidget);
    expect(find.text(uri), findsOneWidget);
  });

  testWidgets('tapping Copy writes the URI to the clipboard and flips the label',
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
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpScreen(tester, _ControlledCreateGateway(uri));

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
    await pumpScreen(tester, _ControlledCreateGateway('mosh://invite?back=1'));

    // The step's Back affordance reads the localized "Back" label.
    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Routing returned to '/' (onboarding): the menu screen reappears.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(ChatCreateScreen), findsNothing);
  });
}
