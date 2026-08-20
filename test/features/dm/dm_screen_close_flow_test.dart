// Widget tests for the DM leave/close-session close-flow -- the 1-в-1 port
// of React's `useChatCloseFlow` dm branch (use-chat-close-flow.ts L46-56 +
// L113-119). The leave IconButton (Icons.close, the React IconX in
// ActiveChatHeader `afterSearchActions`, ActiveChatPanes.tsx L122-130) now
// opens a ConfirmDialog (`Delete chat with {label}?` / body / `Delete chat`)
// before the real `_leave` (gateway.leave + fingerprint cleanup + nav
// back) runs. Mirrors the seed/override idiom of
// `channel_screen_close_flow_test.dart` (override `activeSessionProvider` so
// the native cdylib is not involved). The test gateway records the
// `leave` call, so the test asserts the real close only fires on an
// explicit confirm (React's
// `closeFlow.confirmCloseActive` gating the real close).
//
// Three cases:
//   1. Tapping leave opens the ConfirmDialog (title renders with the peer
//      display name + the localized confirm label; gateway not yet called).
//   2. Confirming calls the real `_leave` -> `leave(DmTarget(...))`.
//   3. Cancelling does NOT call `_leave` (no gateway closeSession call).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

SessionSnapshot _snapshot({required String sessionId, required String peerName}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: peerName,
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: 'fp-peer-1234',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

Future<void> _pump(
  WidgetTester tester,
  ScriptableGateway gateway, {
  required String sessionId,
  required String peerName,
}) async {
  // Use the real appRouter so `context.go(AppRoutes.sessions)` after a
  // confirmed close does not throw (mirrors
  // `channel_screen_close_flow_test.dart`).
  final router = GoRouter(
    initialLocation: AppRoutes.dmFor(sessionId),
    routes: appRouter.configuration.routes,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      activeSessionProvider(sessionId)
          .overrideWith((ref) async => _snapshot(sessionId: sessionId, peerName: peerName)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const sessionId = 'dm-close-1';
  const peerName = 'juno-phone';

  testWidgets('tapping leave opens the ConfirmDialog with the peer name',
      (tester) async {
    final gateway = ScriptableGateway();
    await _pump(tester, gateway, sessionId: sessionId, peerName: peerName);

    // The leave IconButton (Icons.close, React IconX) opens the close-flow
    // dialog.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // React `Delete chat with ${label}?` -> ARB `deleteChatTitle` renders the
    // peer display name.
    expect(find.text('Delete chat with $peerName?'), findsOneWidget);
    // The localized confirm button label renders.
    expect(find.text('Delete chat'), findsOneWidget);
    // The gateway close has NOT fired yet (dialog is open, unconfirmed).
    expect(gateway.countOf(GatewayMethod.leave), 0);
  });

  testWidgets('confirming calls leave (the real _leave)',
      (tester) async {
    final gateway = ScriptableGateway();
    await _pump(tester, gateway, sessionId: sessionId, peerName: peerName);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Tap the danger confirm button (labeled with the localized confirmLabel).
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();

    // The real close fired with the sessionId.
    expect(gateway.lastCall(GatewayMethod.leave)?.target, DmTarget(sessionId));
  });

  testWidgets('cancelling does NOT call leave', (tester) async {
    final gateway = ScriptableGateway();
    await _pump(tester, gateway, sessionId: sessionId, peerName: peerName);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Cancel via the ghost TextButton (localized `dialogCancel` -> "Cancel").
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No real close fired.
    expect(gateway.countOf(GatewayMethod.leave), 0);
    // The dialog is gone and the DM screen is still mounted.
    expect(find.text('Delete chat with $peerName?'), findsNothing);
    expect(find.byType(DmScreen), findsOneWidget);
  });
}
