// Unit + widget tests for the group message grouping + multi-party
// sender-meta port of React `GroupMessageRow` / `GroupChatList`
// (src/features/private-dm/MessageLists.tsx). The pure `groupGroupMessages`
// helper is the public seam; the widget test pumps GroupScreen with
// `groupSnapshotProvider` overridden to return a GroupSnapshot seeded with
// two grouped peer messages from the same fingerprint and asserts exactly
// one sender-meta row (the first of the group) renders, confirming the
// grouped row omits the meta. Mirrors `dm_screen_grouping_test.dart` and
// `channel_screen_grouping_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/group/group_message_row.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

GroupMessage _msg({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  BigInt? sentAtMs,
}) =>
    GroupMessage(
      fromDevice: fromDevice,
      fromFingerprint: fromFingerprint,
      body: body,
      messageId: null,
      sentAtMs: sentAtMs,
      attachment: null,
      deliveryStatus: null,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

GroupSnapshot _snapshot({
  required String groupId,
  required String deviceFingerprint,
  required List<GroupMessage> messages,
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      label: null,
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      creatorFingerprint: deviceFingerprint,
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(2),
      inviteUri: null,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

void main() {
  // `formatClock` in the sender-meta row formats via `intl`'s `DateFormat`;
  // `main()` (which calls `initializeDateFormatting`) is bypassed under
  // `flutter test`, so load the date symbols here so the timestamp renders
  // with the resolved locale (en by default).
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('groupGroupMessages', () {
    test('single message is never grouped', () {
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: BigInt.from(1700000000000)),
      ]);
      expect(result.length, 1);
      expect(result.first.grouped, false);
    });

    test('same fingerprint within 5 min groups the second', () {
      final base = BigInt.from(1700000000000);
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, true]);
    });

    test('same DISPLAY name but DIFFERENT fingerprint does NOT group', () {
      // Groups are multi-party: two members could share a display name but
      // never a device fingerprint -- the grouping key is the fingerprint.
      final base = BigInt.from(1700000000000);
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-bob',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, false]);
    });

    test('same fingerprint 10 min apart does NOT group', () {
      final base = BigInt.from(1700000000000);
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'b',
            sentAtMs: base + BigInt.from(10 * 60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, false]);
    });

    test('different fingerprints never group', () {
      final base = BigInt.from(1700000000000);
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: base),
        _msg(
            fromDevice: 'bob',
            fromFingerprint: 'fp-bob',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, false]);
    });

    test('null sentAtMs breaks grouping for the next message', () {
      final base = BigInt.from(1700000000000);
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: null),
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, false]);
    });

    test('three clustered + one later: only first + later are not grouped', () {
      final base = BigInt.from(1700000000000);
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'b',
            sentAtMs: base + BigInt.from(60 * 1000)),
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'c',
            sentAtMs: base + BigInt.from(2 * 60 * 1000)),
        // 10 min after the first -> new group.
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'd',
            sentAtMs: base + BigInt.from(10 * 60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, true, true, false]);
    });

    test('exactly 5 min boundary groups (<= window)', () {
      final base = BigInt.from(1700000000000);
      final result = groupGroupMessages([
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'a',
            sentAtMs: base),
        _msg(
            fromDevice: 'alice',
            fromFingerprint: 'fp-alice',
            body: 'b',
            sentAtMs: base + BigInt.from(5 * 60 * 1000)),
      ]);
      expect(result.map((e) => e.grouped), [false, true]);
    });
  });

  // The widget test drives the screen via a `groupSnapshotProvider` override
  // (the public FutureProvider.family seam) so the controlled messages are
  // deterministic and the gateway / native cdylib are not involved. We
  // seed two peer messages from `bob` (fingerprint `fp-bob`) one minute
  // apart; the second groups under the first, so exactly one sender-meta row
  // should render (device name + fingerprint + HH:mm clock each appearing
  // exactly once for the first message).
  testWidgets('two grouped group messages render exactly one sender-meta',
      (tester) async {
    const groupId = 'group-1';
    final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      messages: [
        _msg(
            fromDevice: 'bob',
            fromFingerprint: 'fp-bob',
            body: 'first',
            sentAtMs: base),
        _msg(
            fromDevice: 'bob',
            fromFingerprint: 'fp-bob',
            body: 'second',
            sentAtMs: base + BigInt.from(60 * 1000)),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        groupSnapshotProvider(groupId).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupScreen(groupId: groupId),
      ),
    ));
    await tester.pumpAndSettle();

    // Both bubble bodies render.
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    // Exactly one sender-meta row: the device name 'bob' appears once (it
    // would appear twice -- once per row -- without grouping).
    expect(find.text('bob'), findsOneWidget);

    // The shortened fingerprint (shorten('fp-bob', 6) -> 'fp-bob', since the
    // value is shorter than head*2+1 = 13 chars) appears exactly once.
    expect(find.text('fp-bob'), findsOneWidget);

    // The HH:mm clock is locale-aware + in the LOCAL timezone (1-1 with
    // React's `toLocaleTimeString`), so the expected string is derived from
    // the same epoch the way `formatClock` does -- timezone-agnostic.
   final expectedClock = DateFormat.Hm('en')
       .format(DateTime.fromMillisecondsSinceEpoch(base.toInt()).toLocal());
   expect(find.text(expectedClock), findsOneWidget);
 });

  // Regression: own non-grouped messages MUST render the sender meta (React
  // `GroupMessageRow` shows meta unconditionally on non-grouped rows,
  // including the user's own -- `PeerNickname` bolds the own name). The
  // initial port gated meta with `!own && !grouped`, suppressing it on own
  // rows; this test pins the fixed `if (!grouped)` gate.
  testWidgets('own non-grouped group message renders sender-meta + MLS badge',
      (tester) async {
    const groupId = 'group-own';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      messages: [
        _msg(
            fromDevice: 'me',
            fromFingerprint: 'fp-me',
            body: 'my own message',
            sentAtMs: BigInt.from(1700000000000)),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        groupSnapshotProvider(groupId).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupScreen(groupId: groupId),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('my own message'), findsOneWidget);
    // Own device name renders (was suppressed by the old `!own` gate).
    expect(find.text('me'), findsOneWidget);
    // Own fingerprint renders.
    expect(find.text('fp-me'), findsOneWidget);
    // Group rows DO render the MLS badge (React GroupMessageRow includes it,
    // unlike ChannelMessageRow). Pins the group-vs-channel badge parity.
    expect(find.text('MLS'), findsOneWidget);
  });
}
