// Widget tests pinning the rail active-highlight parity gap (React
// SessionRail rail-item-active, SessionRail.tsx:254-296): the open DM's rail
// row is the single selected row; with no active conversation (null key) NO
// row is selected. Mirrors the established sessions-screen test setup: a
// seeded fake gateway returning 2 DM sessions, a localized MaterialApp, and
// a ProviderScope. The active key is set via the real notifier
// (container.read(activeConversationKeyProvider.notifier).set(key)) before
// the first pump so SessionsScreen's ref.watch reads the fixed value on
// first build. This avoids overriding the NotifierProvider with a subclass
// (the real notifier _ActiveConversationKeyNotifier is private to its
// library, so overrideWith cannot name the type) and exercises the same
// set path the rail + chat screens use in production.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';

// Seeded fake gateway returning a fixed 2-session snapshot so the rail
// renders two deterministic DM rows (Alice + Bob).
SessionSnapshot _session({
  required String sessionId,
  required String peerDisplayName,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: peerDisplayName,
      state: 'ready',
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
  const aliceId = 'alice-session';
  const bobId = 'bob-session';
  final gateway = ScriptableGateway()..seedSessions([
    _session(sessionId: aliceId, peerDisplayName: 'Alice'),
    _session(sessionId: bobId, peerDisplayName: 'Bob'),
  ]);

  // Pumps SessionsScreen with the seeded gateway + the active key pre-set
  // to activeKey (null => no open conversation). The active key is set on
  // the real notifier before the first pump so the watch reads it on first
  // build; set short-circuits when value equals current state (null==null),
  // so the null case needs no call.
  Future<void> pumpScreen(
    WidgetTester tester, {
    String? activeKey,
  }) async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    if (activeKey != null) {
      container.read(activeConversationKeyProvider.notifier).set(activeKey);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SessionsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // Finds the RailItem whose title matches label (the DM row label) and
  // returns its active flag. Each row's title is the peer display name, so
  // this reliably resolves the right row.
  bool? selectedFor(WidgetTester tester, String label) {
    for (final item in tester.widgetList<RailItem>(find.byType(RailItem))) {
      if (item.title == label) return item.active;
    }
    return null;
  }

  testWidgets(
      'open DM row is selected when activeConversationKey matches dm:<id>',
      (tester) async {
    await pumpScreen(tester, activeKey: 'dm:$aliceId');

    // The open conversation's row (Alice) is the selected row.
    expect(selectedFor(tester, 'Alice'), isTrue);
    // The other DM row (Bob) is not selected.
    expect(selectedFor(tester, 'Bob'), isFalse);
  });

  testWidgets(
      'no row is selected when activeConversationKey is null (no open chat)',
      (tester) async {
    await pumpScreen(tester, activeKey: null);

    expect(selectedFor(tester, 'Alice'), isFalse);
    expect(selectedFor(tester, 'Bob'), isFalse);
  });
}
