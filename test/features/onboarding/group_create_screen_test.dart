// Widget tests for the GroupCreateScreen (group-create step). Mirrors the
// channel_join_screen_test boilerplate: ProviderScope override of
// `gatewayProvider` with the test gateway + localized MaterialApp.router so
// the step's Back button (context.go) resolves.
//
// Test 1: initial state -- title + body + placeholder + button label
//   (Create, not Recreate -- no invite exists).
// Test 2: Create button is enabled even when the label is empty (only the
//   busy flag gates the button -- the group label is OPTIONAL).
// Test 3: tapping Create calls the gateway's createGroup (canned
//   GroupCreated) and renders the InviteResult card with the invite URI +
//   flips the button label to Recreate (slice-3 seam).
// Test 4: Back button returns to the onboarding menu.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/features/onboarding/group_create_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/state/gateway_provider.dart'
    show bridgeFacadeProvider, gatewayProvider;
import '../../support/pump.dart';

const _groupStepBody =
    'Spin up an MLS-encrypted group. You admit members and stay the admin.';

/// Stubs the flutter/services clipboard channel so the auto-copy on create
/// does not hang the test waiting on a real platform channel.
/// Clipboard.setData is the only platform call this screen makes.
void _stubClipboard() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

void main() {
  Future<void> pumpGroupStep(
    WidgetTester tester, {
    BridgeFacade? bridge,
    String initialLocation = AppRoutes.groupCreate,
  }) {
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge ?? ScriptableBridge()),
    ]);
    addTearDown(container.dispose);
    return pumpRoute(tester, initialLocation, container: container);
  }

  testWidgets(
      'initial state renders title, body, placeholder, and Create button label',
      (tester) async {
    await pumpGroupStep(tester);

    // Title (onboardTileGroupTitle) + body (onboardGroupStepBody) +
    // placeholder (onboardGroupNamePlaceholder) + button (onboardGroupCreate,
    // NOT onboardGroupRecreate since no invite exists).
    expect(find.text('New group'), findsOneWidget);
    expect(find.text(_groupStepBody), findsOneWidget);
    expect(find.text('Group name (optional)'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
    expect(find.text('Replace group invite'), findsNothing);
  });

  testWidgets('Create button is enabled even when the label is empty',
      (tester) async {
    await pumpGroupStep(tester);

    // No text entered -> the button is still enabled (the gate is `busy`
    // only, NOT an empty label -- the group label is optional).
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
      'tapping Create creates via the gateway and renders the InviteResult card with the invite URI',
      (tester) async {
    final gateway = ScriptableBridge();
    await pumpGroupStep(tester, bridge: gateway);

    _stubClipboard();

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
    expect(gateway.countOf(BridgeMethod.listGroups), 2);
  });

  testWidgets('Back button returns to the onboarding menu', (tester) async {
    await pumpGroupStep(tester);

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
    final throwing = ScriptableBridge()
      ..failAlways(BridgeMethod.createGroup, error: message);

    _stubClipboard();

    await pumpGroupStep(tester, bridge: throwing);

    await tester.enterText(find.byType(TextField), 'friends');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // A non-bridge error renders as its own text (the classifier's text
    // arm) and the inline error is the ONE source of feedback -- no
    // transient SnackBar.
    expect(find.text(message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(throwing.countOf(BridgeMethod.listGroups), 0);
  });

  testWidgets('Open group lands on the group just created', (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    await pumpRoute(tester, AppRoutes.groupCreate, overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      gatewayProvider.overrideWithValue(gateway),
    ]);
    _stubClipboard();

    await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open group'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupScreen), findsOneWidget);
    expect(find.byType(GroupCreateScreen), findsNothing);
  });
}
