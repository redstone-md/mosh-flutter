// Focused coverage for the React-parity SessionRail New action. Both entry
// points must open the existing NewSessionPanel without creating an invite or
// showing a transient SnackBar, on desktop and mobile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/main.dart';
import 'package:mosh/src/features/onboarding/new_session_panel.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

Future<ProviderContainer> _pumpSessions(
  WidgetTester tester,
  ScriptableGateway gateway, {
  required Size physicalSize,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  appRouter.go(AppRoutes.sessions);
  final container = ProviderContainer(
    overrides: [gatewayProvider.overrideWithValue(gateway)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MoshApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('empty CTA opens NewSessionPanel without creating an invite',
      (tester) async {
    final gateway = ScriptableGateway();
    await _pumpSessions(tester, gateway, physicalSize: const Size(400, 800));

    expect(find.byType(SessionsScreen), findsOneWidget);
    await tester.tap(find.text('New private chat'));
    await tester.pumpAndSettle();

    expect(find.byType(NewSessionPanel), findsOneWidget);
    expect(find.byType(ChatPaneWelcome), findsOneWidget);
    expect(find.byType(SessionsScreen), findsNothing);
    expect(gateway.countOf(GatewayMethod.createInvite), 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'rail New button opens NewSessionPanel on desktop without creating an invite',
      (tester) async {
    final gateway = ScriptableGateway();
    await _pumpSessions(tester, gateway, physicalSize: const Size(1200, 900));

    expect(find.byType(SessionsScreen), findsOneWidget);
    await tester.tap(find.byType(RailNewButton));
    await tester.pumpAndSettle();

    expect(find.byType(NewSessionPanel), findsOneWidget);
    expect(find.byType(ChatPaneWelcome), findsOneWidget);
    expect(gateway.countOf(GatewayMethod.createInvite), 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'rail New button opens NewSessionPanel on mobile without creating an invite',
      (tester) async {
    final gateway = ScriptableGateway();
    await _pumpSessions(tester, gateway, physicalSize: const Size(400, 800));

    expect(find.byType(SessionsScreen), findsOneWidget);
    await tester.tap(find.byType(RailNewButton));
    await tester.pumpAndSettle();

    expect(find.byType(NewSessionPanel), findsOneWidget);
    expect(find.byType(ChatPaneWelcome), findsOneWidget);
    expect(find.byType(SessionsScreen), findsNothing);
    expect(gateway.countOf(GatewayMethod.createInvite), 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('New resets a previous invite before showing the panel',
      (tester) async {
    final gateway = ScriptableGateway();
    final container = await _pumpSessions(
      tester,
      gateway,
      physicalSize: const Size(1200, 900),
    );

    await container.read(inviteFlowProvider.notifier).create();
    expect(gateway.countOf(GatewayMethod.createInvite), 1);
    await tester.tap(find.byType(RailNewButton));
    await tester.pumpAndSettle();

    expect(container.read(inviteFlowProvider).lastInvite, isNull);
    expect(find.byType(NewSessionPanel), findsOneWidget);
    expect(gateway.countOf(GatewayMethod.createInvite), 1);
  });
}
