// Widget tests for the GroupCreateScreen (group-create step, mirrors the
// React GroupCreateStep). Mirrors the channel_join_screen_test boilerplate:
// ProviderScope override of `gatewayProvider` with the test gateway + localized
// MaterialApp.router so the step's Back button (context.go) resolves.
//
// Test 1: initial state -- title + body + placeholder + button label
//   (Create, not Recreate -- no invite exists).
// Test 2: Create button is enabled even when the label is empty (React
//   `disabled={busy}` only -- the group label is OPTIONAL).
// Test 3: tapping Create calls the gateway's createGroup (canned
//   GroupCreated) and renders the InviteResult card with the invite URI +
//   flips the button label to Recreate (slice-3 seam).
// Test 4: Back button returns to the onboarding menu.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/group_create_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

const _groupStepBody =
    'Spin up an MLS-encrypted group. You admit members and stay the admin.';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    Gateway? gateway,
    String initialLocation = AppRoutes.groupCreate,
  }) async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway ?? ScriptableGateway()),
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
  }

  testWidgets(
      'initial state renders title, body, placeholder, and Create button label',
      (tester) async {
    await pumpScreen(tester);

    // Title (onboardTileGroupTitle) + body (onboardGroupStepBody) +
    // placeholder (onboardGroupNamePlaceholder) + button (onboardGroupCreate,
    // NOT onboardGroupRecreate since no invite exists).
    expect(find.text('New group'), findsOneWidget);
    expect(find.text(_groupStepBody), findsOneWidget);
    expect(find.text('Group name (optional)'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
    expect(find.text('Replace group invite'), findsNothing);
  });

  testWidgets(
      'Create button is enabled even when the label is empty (React disabled={busy} only)',
      (tester) async {
    await pumpScreen(tester);

    // No text entered -> the button is still enabled (React disables on
    // `busy` only, NOT on an empty label -- the group label is optional).
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
      'tapping Create creates via the gateway and renders the InviteResult card with the invite URI',
      (tester) async {
    final gateway = ScriptableGateway();
    await pumpScreen(tester, gateway: gateway);

    // Intercept the flutter/services clipboard method channel so the
    // auto-copy on create (React `copyText(created.invite_uri)`) does not
    // hang the test waiting on a real platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      // Clipboard.setData is the only platform call this screen makes.
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    // Enter a label so the canned GroupCreated invite URI is deterministic
    // (the gateway derives it from the label).
    await tester.enterText(find.byType(TextField), 'friends');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // The createGroup seam (slice-3) calls the gateway's createGroup (returns
    // a canned GroupCreated with invite URI `mosh://group/fake-group-friends`)
    // and renders the InviteResult card with that URI. No SnackBar on the
    // happy path; the button label flips to Recreate.
    expect(find.byType(InviteResult), findsOneWidget);
    expect(find.text('mosh://group/fake-group-friends'), findsOneWidget);
    expect(find.text('Replace group invite'), findsOneWidget);
    expect(find.text('Create group'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Reading the notifier initializes it once, then the explicit refresh
    // performs the post-create fetch. Pin both calls so this cannot pass on
    // provider initialization alone.
    expect(gateway.countOf(GatewayMethod.listGroups), 2);
  });

  testWidgets('Back button returns to the onboarding menu', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Routing returned to '/' (onboarding): the menu screen reappears and
    // the step screen is gone.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(GroupCreateScreen), findsNothing);
  });

  testWidgets(
      'a failed create surfaces a persistent inline error (role="alert") and no SnackBar',
      (tester) async {
    const message = 'Group runtime offline';
    final throwing = ScriptableGateway()..failAlways(GatewayMethod.createGroup, error: message);

    // Intercept the flutter/services clipboard channel so the auto-copy on
    // create does not hang the test on a real platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpScreen(tester, gateway: throwing);

    await tester.enterText(find.byType(TextField), 'friends');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // The inline error renders the raw error string verbatim (React
    // `{props.error}` stringifies the caught error) and is the ONE source
    // of feedback -- no transient SnackBar (the old SnackBar path is gone).
    expect(find.text(message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(throwing.countOf(GatewayMethod.listGroups), 0);
  });
}
