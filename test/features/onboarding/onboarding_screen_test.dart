// S4.4: widget test for the slice-one onboarding screen.
// Per ADR 0013 + S5 the gatewayProvider default is RealBridgeGateway (real
// Rust), which cannot run under `flutter test` (no native cdylib). The
// container must override gatewayProvider with FakeGateway so any
// provider-backed read stays deterministic (the Chat tile no longer creates
// an invite inline -- it navigates to /chat-create -- but the override
// stays so the provider stays wired in this pump).
//
// S2-1+chat-create: tapping "New private chat" now navigates to the
// chat-create step (AppRoutes.chatCreate) instead of showing a SnackBar.
// The test pumps the screen through the real appRouter (MaterialApp.router)
// so context.go resolves and the ChatCreateScreen renders after the tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_screen.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

void main() {
 testWidgets('onboarding renders title, binds name to inviteFlow, chat tile taps', (tester) async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(FakeGateway()),
    ]);
    addTearDown(container.dispose);

    // Use a GoRouter built from the appRouter route table so the Chat
    // tile's context.go(AppRoutes.chatCreate) resolves to ChatCreateScreen.
    final router = GoRouter(
      initialLocation: AppRoutes.onboarding,
      routes: appRouter.configuration.routes,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Title resolves from the ARB (en) -> "Start a conversation".
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);

    // Entering text must flow into inviteFlowProvider.displayName.
    await tester.enterText(find.byType(TextField), 'juno-laptop');
    await tester.pump();
    expect(container.read(inviteFlowProvider).displayName, 'juno-laptop');

    // Tapping the Chat tile navigates to /chat-create (the ChatCreateScreen
    // step), replacing the old SnackBar placeholder. No SnackBar renders.
    await tester.tap(find.text('New private chat'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatCreateScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
