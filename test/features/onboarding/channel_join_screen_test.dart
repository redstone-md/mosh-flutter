// Widget tests for the ChannelJoinScreen (channel-join step, 1-в-1 with the
// React ChannelJoinStep). Mirrors the chat_create_screen_test boilerplate:
// ProviderScope override of `gatewayProvider` with FakeGateway + localized
// MaterialApp.router so the step's Back button (context.go) resolves.
//
// Test 1: initial state -- title + body + placeholder + `#` + button label.
// Test 2: Join button is disabled when the name is empty; enabling on text.
// Test 3: tapping Join (with a name entered) calls FakeGateway.joinChannel
//   (canned snapshot) and navigates to the channel screen (slice-3 seam).
// Test 4: Back button returns to the onboarding menu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/channel/channel_screen.dart';
import 'package:mosh/src/features/onboarding/channel_join_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    String initialLocation = AppRoutes.channelJoin,
  }) async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(FakeGateway()),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: initialLocation,
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
    return router;
  }

  testWidgets(
      'initial state renders title, body, placeholder, `#` prefix, and button label',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Join a public channel'), findsOneWidget);
    expect(
      find.text(
        'Public channels are not end-to-end encrypted \u2014 anyone who knows the name can read along.',
      ),
      findsOneWidget,
    );
    expect(find.text('channel-name'), findsOneWidget);
    expect(find.text('Join channel'), findsOneWidget);
    expect(find.text('#'), findsOneWidget);
  });

  testWidgets(
      'Join button is disabled when name is empty and enabled after text entry',
      (tester) async {
    await pumpScreen(tester);

    // Empty name -> disabled (onPressed is null).
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    // Enter text -> enabled (onPressed is not null).
    await tester.enterText(find.byType(TextField), 'test-channel');
    await tester.pump();
    final enabledButton =
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets(
      'tapping Join with a name entered joins via the gateway and navigates to the channel screen',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'test-channel');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // The joinChannel seam (slice-3) calls FakeGateway.joinChannel (returns
    // a canned ChannelSnapshot for 'test-channel') and navigates to the
    // channel screen. No SnackBar on the happy path.
    expect(find.byType(ChannelScreen), findsOneWidget);
    expect(find.byType(ChannelJoinScreen), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Back button returns to the onboarding menu', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Routing returned to '/' (onboarding): the menu screen reappears and
    // the step screen is gone.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(ChannelJoinScreen), findsNothing);
  });
}
