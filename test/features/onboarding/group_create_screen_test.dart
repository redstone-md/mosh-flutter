// Widget tests for the GroupCreateScreen (group-create step, mirrors the
// React GroupCreateStep). Mirrors the channel_join_screen_test boilerplate:
// ProviderScope override of `gatewayProvider` with FakeGateway + localized
// MaterialApp.router so the step's Back button (context.go) resolves.
//
// Test 1: initial state -- title + body + placeholder + button label
//   (Create, not Recreate -- no invite exists).
// Test 2: Create button is enabled even when the label is empty (React
//   `disabled={busy}` only -- the group label is OPTIONAL).
// Test 3: tapping Create shows the "later slice" SnackBar (Gateway
//   createGroup seam is deferred -> honest stub).
// Test 4: Back button returns to the onboarding menu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/group_create_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

const _groupStepBody =
    'Spin up an MLS-encrypted group. You admit members and stay the admin.';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    String initialLocation = AppRoutes.groupCreate,
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
      'tapping Create shows the later-slice SnackBar stub (createGroup seam deferred)',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // The Gateway createGroup seam is deferred; the button honestly shows
    // the "later slice" SnackBar instead of calling a gateway method.
    expect(find.byType(SnackBar), findsOneWidget);
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
}
