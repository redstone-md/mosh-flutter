// Unit + widget tests for the DM message grouping + sender-meta port of
// React `DmMessageRow` (src/features/private-dm/MessageLists.tsx). The pure
// `groupDmMessages` helper is the @visibleForTesting seam; the widget test
// pumps DmScreen with `activeSessionProvider` overridden to return a
// SessionSnapshot seeded with two grouped messages from the same sender and
// asserts exactly one sender-meta row (the first of the group) renders,
// confirming the grouped row omits the meta.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/features/dm/dm_message_list.dart';
import 'package:mosh/src/features/dm/dm_message_row.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/session_providers.dart';

ChatMessage _msg({
  required String fromDevice,
  required String body,
  BigInt? sentAtMs,
}) =>
    ChatMessage(
      fromDevice: fromDevice,
      body: body,
      messageId: null,
      sentAtMs: sentAtMs,
      attachment: null,
      callEvent: null,
      deliveryStatus: null,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

SessionSnapshot _snapshot({
  required String sessionId,
  required String displayName,
  required List<ChatMessage> messages,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: '',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: '0123456789abcdef',
      messages: messages,
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

void main() {
  // `formatClock` in the sender-meta row now formats via `intl`'s
  // `DateFormat`; `main()` (which calls `initializeDateFormatting`) is
  // bypassed under `flutter test`, so load the date symbols here so the
  // timestamp renders with the resolved locale (en by default).
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('groupDmMessages', () {
    test('single message is never grouped', () {
      final result = groupDmMessages([
        _msg(
            fromDevice: 'alice',
            body: 'a',
            sentAtMs: BigInt.from(1700000000000)),
      ]);
      expect(result.length, 1);
      expect(result.first.grouped, false);
    });

    test('same sender within 5 min groups the second', () {
      final base = BigInt.from(1700000000000);
      final result = groupDmMessages([
        _msg(fromDevice: 'alice', body: 'a', sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, true]);
    });

    test('same sender 10 min apart does NOT group', () {
      final base = BigInt.from(1700000000000);
      final result = groupDmMessages([
        _msg(fromDevice: 'alice', body: 'a', sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            body: 'b',
            sentAtMs: base + BigInt.from(10 * 60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, false]);
    });

    test('different senders never group', () {
      final base = BigInt.from(1700000000000);
      final result = groupDmMessages([
        _msg(fromDevice: 'alice', body: 'a', sentAtMs: base),
        _msg(
            fromDevice: 'bob',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, false]);
    });

    test('null sentAtMs breaks grouping for the next message', () {
      final base = BigInt.from(1700000000000);
      final result = groupDmMessages([
        _msg(fromDevice: 'alice', body: 'a', sentAtMs: null),
        _msg(
            fromDevice: 'alice',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, false]);
    });

    test('three clustered + one later: only first + later are not grouped', () {
      final base = BigInt.from(1700000000000);
      final result = groupDmMessages([
        _msg(fromDevice: 'alice', body: 'a', sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
        _msg(
            fromDevice: 'alice',
            body: 'c',
            sentAtMs: base + BigInt.from(2 * 60 * 1000)),
        // 10 min after the first -> new group.
        _msg(
            fromDevice: 'alice',
            body: 'd',
            sentAtMs: base + BigInt.from(10 * 60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, true, true, false]);
    });

    test('exactly 5 min boundary groups (<= window)', () {
      final base = BigInt.from(1700000000000);
      final result = groupDmMessages([
        _msg(fromDevice: 'alice', body: 'a', sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            body: 'b',
            sentAtMs: base + BigInt.from(5 * 60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, true]);
    });
  });

  // The widget test drives the screen via an `activeSessionProvider` override
  // (the public FutureProvider.family seam) so the controlled messages are
  // deterministic and the gateway / native cdylib are not involved. We
  // seed two peer messages from `bob` one minute apart; the second groups
  // under the first, so exactly one sender-meta row should render (with the
  // device name + the HH:mm timestamp each appearing exactly once).
  testWidgets('two grouped messages render exactly one sender-meta row',
      (tester) async {
    const sessionId = 'sess-1';
    final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z
    final snapshot = _snapshot(
      sessionId: sessionId,
      displayName: 'alice',
      messages: [
        _msg(fromDevice: 'bob', body: 'first', sentAtMs: base),
        _msg(
            fromDevice: 'bob',
            body: 'second',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeSessionProvider(sessionId).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DmScreen(sessionId: sessionId),
      ),
    ));
    await tester.pumpAndSettle();

    // Both bubble bodies render.
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    // Exactly one sender-meta row: the device name 'bob' appears once in a
    // message row (it would appear twice -- once per row -- without
    // grouping) and the HH:mm clock appears exactly once for the first
    // message. Scoped to DmMessageRow because the DM AppBar title now also
    // shows the peer name (React `peerLabel` parity), so an unscoped
    // find.text('bob') would also match the header title.
    expect(
      find.descendant(
        of: find.byType(DmMessageRow),
        matching: find.text('bob'),
      ),
      findsOneWidget,
    );

    // The HH:mm clock is locale-aware + in the LOCAL timezone (1-1 with
    // React's `toLocaleTimeString`), so the expected string is derived
    // from the same epoch the way `formatClock` does -- timezone-agnostic
    // (passes on any host tz, not just UTC).
    final expectedClock = DateFormat.Hm('en')
        .format(DateTime.fromMillisecondsSinceEpoch(base.toInt()).toLocal());
    expect(find.text(expectedClock), findsOneWidget);
  });
}
