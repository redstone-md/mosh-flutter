// Widget tests for the SessionsScreen (DM sessions list). Mirrors the
// established slice-one pattern: ProviderScope override of `gatewayProvider`
// with a controllable fake + a localized MaterialApp. Test 3 (error/retry)
// uses a counting fake so we can assert `listSessions` ran a second time
// after tapping Retry. Test 2 wraps the screen in the real `appRouter` via
// `MaterialApp.router` so `context.go(AppRoutes.dmFor(...))` resolves and
// pushes DmScreen, which the test asserts by the DM screen's composer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/unread_providers.dart';

/// A FakeGateway subclass whose `listSessions` returns a fixed snapshot so
/// the screen renders a deterministic non-empty list (test 2 + label/state
/// assertions). createInvite is left inherited (test 1 uses the empty list
/// returned by the base FakeGateway with no pre-seeded sessions).
class _SeededSessionsGateway extends FakeGateway {
  _SeededSessionsGateway(this._sessions);

  final List<SessionSnapshot> _sessions;

  @override
  Future<SessionListSnapshot> listSessions() =>
      Future.value(SessionListSnapshot(sessions: _sessions));
}

/// A fake that always errors on `listSessions` and counts the calls so the
/// retry test can assert refresh re-invoked the gateway.
class _FailingListGateway extends FakeGateway {
  int listCalls = 0;

  @override
  Future<SessionListSnapshot> listSessions() {
    listCalls++;
    return Future.error(Exception('boom-listSessions'));
  }
}

SessionSnapshot _session({
  required String sessionId,
  required String displayName,
  required String peerDisplayName,
  required String state,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      path: 'connecting',
      relayReady: null,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Gateway gateway, {
    bool useRouter = false,
    String initialLocation = AppRoutes.sessions,
  }) async {
    if (useRouter) {
      // Use the real appRouter so context.go navigation resolves. The
      // initialLocation is forced to /sessions for these tests.
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
    } else {
      await tester.pumpWidget(ProviderScope(
        overrides: [gatewayProvider.overrideWithValue(gateway)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SessionsScreen(),
        ),
      ));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('empty list renders the welcome + start-cta button', (tester) async {
    // Base FakeGateway has no pre-seeded sessions, so listSessions is empty.
    await pumpScreen(tester, FakeGateway());

    expect(find.text('Welcome to Mosh.'), findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);
  });

  testWidgets('non-empty list renders rows with label + state, tapping navigates to dm',
      (tester) async {
    const aliceId = 'alice-session';
    const bobId = 'bob-session';
    final gateway = _SeededSessionsGateway([
      _session(
          sessionId: aliceId,
          displayName: 'me',
          peerDisplayName: 'Alice',
          state: 'ready'),
      _session(
          sessionId: bobId,
          displayName: 'Bob',
          peerDisplayName: '',
          state: 'connecting'),
    ]);

    await pumpScreen(tester, gateway, useRouter: true);

    // Both rows render with their labels and localized state labels.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget); // ready -> stateReady
    expect(find.text('Waiting'), findsOneWidget); // connecting -> stateWaiting

    // Accessibility: the Alice row exposes the React-parity semantics label.
    expect(find.bySemanticsLabel('Open session with Alice'), findsOneWidget);

    // Tapping the Alice row navigates to /dm/<aliceId>. The DM screen's
    // composer placeholder is a stable sentinel that the router pushed it.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Write a message\u2026'), findsOneWidget);
  });

  testWidgets('error state renders retry and tapping it calls listSessions again',
      (tester) async {
    final gateway = _FailingListGateway();
    await pumpScreen(tester, gateway);

    expect(find.text('Could not load sessions.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final callsBefore = gateway.listCalls;

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

  // refresh() re-ran the gateway query (the count must increase, even if
  // Riverpod re-executed build() during settling -- we only assert growth).
  expect(gateway.listCalls, greaterThan(callsBefore));
});

// Unread-badge rendering. Mirrors React's `UnreadBadge`: a row whose
// unread count > 0 shows the numeral; a row with count 0 shows no badge.
// Both `sessionListProvider` (via a seeded gateway) and
// `unreadDmCountsProvider` are overridden so the rendered counts are
// deterministic and do not depend on the seeded messages.
testWidgets('renders an unread badge for sessions with count > 0 and none for 0',
    (tester) async {
  const aliceId = 'alice-unread';
  const bobId = 'bob-read';
  final gateway = _SeededSessionsGateway([
    _session(
        sessionId: aliceId,
        displayName: 'me',
        peerDisplayName: 'Alice',
        state: 'ready'),
    _session(
        sessionId: bobId,
        displayName: 'me',
        peerDisplayName: 'Bob',
        state: 'ready'),
  ]);

  // Only Alice has unread messages; Bob's count is 0.
  final unread = {'dm:$aliceId': 3};

  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      unreadDmCountsProvider.overrideWith((ref) async => unread),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SessionsScreen(),
    ),
  ));
  await tester.pumpAndSettle();

  // One UnreadBadge renders with count 3, and the numeral '3' is visible.
  expect(find.byWidgetPredicate((w) => w is UnreadBadge && w.count == 3),
      findsOneWidget);
  expect(find.text('3'), findsOneWidget);

  // The 0-count row still mounts an UnreadBadge(count: 0) but it renders
  // nothing (SizedBox.shrink) -- so no extra numeral is present and no
  // '99+' ever appears.
  expect(find.byWidgetPredicate((w) => w is UnreadBadge && w.count == 0),
      findsOneWidget);
  expect(find.text('99+'), findsNothing);
});
}
