// Regression test for the mobile dead end.
//
// The shell splits the rail and the chat into two StatefulShellRoute
// branches. On mobile only the active branch renders, and each branch owns
// its own Navigator, so branch B's stack is one deep and `AppBar` implies no
// leading arrow. Opening the new-session pane (`/chat`) therefore left the
// user with nothing on screen that returned to the conversation list -- the
// panel's own Back only rewinds its step menu -- and the app had to be
// restarted. These tests pin that every chat-branch pane exposes a back
// control on mobile, and that it lands on the rail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/features/sessions/sessions_screen.dart';
import '../support/pump.dart';
import '../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// A phone-sized surface: `isMobileBreakpoint` is width <= 580.
const Size _phone = Size(390, 844);

/// A desktop-sized surface, for the negative case.
const Size _desktop = Size(1280, 800);

/// Mounts the app at the rail on a [size]-shaped surface and hands back
/// the router, so a test can drive navigation the way the rail's buttons do.
Future<GoRouter> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return pumpRoute(tester, AppRoutes.sessions,
      overrides: [gatewayProvider.overrideWithValue(ScriptableGateway())]);
}

void main() {
  testWidgets('the new-session pane offers a way back to the rail on mobile',
      (tester) async {
    final router = await _pumpApp(tester, _phone);
    expect(find.byType(SessionsScreen), findsOneWidget);

    // Open the chat branch's welcome pane, the way the rail's New button
    // does.
    router.go(AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(find.byType(SessionsScreen), findsNothing);

    final back = find.byIcon(Icons.arrow_back);
    expect(back, findsOneWidget,
        reason: 'without this the pane is a dead end on mobile');

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('the desktop chat pane has no back control (the rail is live)',
      (tester) async {
    final router = await _pumpApp(tester, _desktop);
    router.go(AppRoutes.chat);
    await tester.pumpAndSettle();

    // Both panes are mounted side by side, so a back control would be a
    // no-op affordance.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byType(SessionsScreen), findsOneWidget);
  });
}
