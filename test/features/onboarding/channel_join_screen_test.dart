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
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// A FakeGateway subclass whose `joinChannel` rejects with a fixed error
/// string so the inline-error path (parity with React role="alert") can be
/// exercised. The error string is asserted verbatim below.
class _RecordingChannelListGateway extends FakeGateway {
  int listChannelsCalls = 0;

  @override
  Future<ChannelListSnapshot> listChannels() async {
    listChannelsCalls++;
    return const ChannelListSnapshot(channels: []);
  }
}

class _ThrowingJoinChannelGateway extends _RecordingChannelListGateway {
  _ThrowingJoinChannelGateway(this._message);

  final String _message;

  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      // Throws the bare message string so `readableError` (the helper the
      // screen captures via) yields the bare message, matching React's
      // `readableError(err)` -> `String(error)` for non-Error values.
      Future.error(_message);
}

void main() {
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    Gateway? gateway,
    String initialLocation = AppRoutes.channelJoin,
  }) async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway ?? FakeGateway()),
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
    final gateway = _RecordingChannelListGateway();
    await pumpScreen(tester, gateway: gateway);

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
    // Reading the notifier initializes the provider once, then the explicit
    // post-join refresh performs the second fetch.
    expect(gateway.listChannelsCalls, 2);
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

  testWidgets(
      'a failed join surfaces a persistent inline error (role="alert") and no SnackBar',
      (tester) async {
    const message = 'Channel runtime offline';
    final throwing = _ThrowingJoinChannelGateway(message);
    await pumpScreen(tester, gateway: throwing);

    await tester.enterText(find.byType(TextField), 'test-channel');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // The inline error renders the raw error string verbatim (React
    // `{props.error}` stringifies the caught error) and is the ONE source
    // of feedback -- no transient SnackBar (the old SnackBar path is gone),
    // and we did NOT navigate to the channel screen.
    expect(find.text(message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(ChannelScreen), findsNothing);
    expect(find.byType(ChannelJoinScreen), findsOneWidget);
    // A failed join must not initialize or refresh the channel list.
    expect(throwing.listChannelsCalls, 0);
  });
}
