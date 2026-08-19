// Widget tests for the DmScreen responsive desktop<->mobile breakpoint
// switch -- the 1-1 port of React's `@media (max-width: 580px)` rule that
// hides the desktop `ConversationTools` row and shows the
// `MobileSearchToggle` header button + `MobileConversationSearch` panel +
// `MobileConversationFilterNotice` strip on narrow widths.
//
// Cases:
//   1. Desktop width (600): the desktop `ConversationTools` row renders and
//      the `MobileSearchToggle` header button is absent.
//   2. Mobile width (400): the `MobileSearchToggle` header button renders
//      and the desktop `ConversationTools` row is absent; tapping the toggle
//      opens `MobileConversationSearch`.
//   3. Changing `sessionId` (the React `resetKey`) closes an open mobile
//      search panel -- `didUpdateWidget` resets `_mobileSearchOpen` to false.
//
// Uses the same fake-gateway-free snapshot-override idiom as
// `conversation_tools_test.dart` (override `activeSessionProvider` so the
// native cdylib is not involved; no send happens so no gateway override is
// needed).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/session_providers.dart';

SessionSnapshot _snapshot({required String sessionId}) => SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: 'peer',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: '0123456789abcdef',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

// The two session ids the reset test re-pumps between. Overriding BOTH up
// front (and reusing the same override list across every pump) keeps the
// ProviderScope's override set stable across re-pumps -- Riverpod throws
// "Tried to update the override of a provider that was not overridden
// before" if the override key set changes between pumpWidget calls, so the
// set must be identical on every re-pump.
const _allSessionIds = ['sess-a', 'sess-b'];

// Pumps DmScreen at the given surface width, overriding the inherited
// MediaQuery so `isMobileBreakpoint` reads the test width (not the default
// 800x600). Re-pumping with a new [sessionId] reuses the DmScreen element
// (same widget type) so `didUpdateWidget` fires -- the path the
// sessionId-reset case exercises.
Future<void> _pumpDm(
  WidgetTester tester, {
  required String sessionId,
  required double width,
}) async {
  await tester.pumpWidget(ProviderScope(
  overrides: [
      for (final id in _allSessionIds)
        activeSessionProvider(id)
            .overrideWith((ref) async => _snapshot(sessionId: id)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: DmScreen(sessionId: sessionId),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'desktop width (600): desktop ConversationTools row present, '
      'MobileSearchToggle absent', (tester) async {
    await _pumpDm(tester, sessionId: 'sess-desktop', width: 600);
    // Desktop: the full ConversationTools row (search TextField +
    // SegmentedButton) renders; the mobile header toggle does not.
    expect(find.byType(ConversationTools), findsOneWidget);
    expect(find.byType(MobileSearchToggle), findsNothing);
    expect(find.byType(MobileConversationSearch), findsNothing);
  });

  testWidgets(
      'mobile width (400): MobileSearchToggle present, desktop row absent; '
      'tapping the toggle opens MobileConversationSearch', (tester) async {
    await _pumpDm(tester, sessionId: 'sess-mobile', width: 400);
    // Mobile: the toggle renders in the AppBar actions; the desktop row
    // does not.
    expect(find.byType(MobileSearchToggle), findsOneWidget);
    expect(find.byType(ConversationTools), findsNothing);
    // The mobile search panel is closed initially.
    expect(find.byType(MobileConversationSearch), findsNothing);

    // Tapping the toggle opens the mobile search panel (autofocusing
    // TextField).
    await tester.tap(find.byType(MobileSearchToggle));
    await tester.pumpAndSettle();
    expect(find.byType(MobileConversationSearch), findsOneWidget);
  });

  testWidgets(
      'changing sessionId resets _mobileSearchOpen to false '
      '(didUpdateWidget reset, React resetKey effect)', (tester) async {
    await _pumpDm(tester, sessionId: 'sess-a', width: 400);
    // Open the mobile search panel.
    await tester.tap(find.byType(MobileSearchToggle));
    await tester.pumpAndSettle();
    expect(find.byType(MobileConversationSearch), findsOneWidget);

    // Re-pump with a NEW sessionId (same DmScreen type so the element is
    // reused and `didUpdateWidget` fires -- the React `resetKey` effect
    // path). The open mobile search panel must close.
    await _pumpDm(tester, sessionId: 'sess-b', width: 400);
    expect(find.byType(MobileConversationSearch), findsNothing);
    // The toggle is still rendered (still mobile width) and back to the
    // closed-state tooltip.
    expect(find.byType(MobileSearchToggle), findsOneWidget);
  });
}
