// Unit + widget tests for the channel message grouping + multi-party
// sender-meta port of React `ChannelMessageRow` / `ChannelChatList`
// (src/features/private-dm/MessageLists.tsx). The pure `groupChannelMessages`
// helper is the public seam; the widget test pumps ChannelScreen with
// `channelSnapshotProvider` overridden to return a ChannelSnapshot seeded
// with two grouped peer messages from the same fingerprint and asserts
// exactly one sender-meta row (the first of the group) renders, confirming
// the grouped row omits the meta. Mirrors `dm_screen_grouping_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/channel/channel_message_row.dart';
import 'package:mosh/src/features/channel/channel_screen.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

ChannelMessage _msg({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  BigInt? sentAtMs,
}) =>
    ChannelMessage(
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

ChannelSnapshot _snapshot({
  required String name,
  required String deviceFingerprint,
  required List<ChannelMessage> messages,
}) =>
    ChannelSnapshot(
      name: name,
      topic: '',
      meshId: 'testmesh',
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

void main() {
  // `formatClock` in the sender-meta row formats via `intl`'s `DateFormat`;
  // `main()` (which calls `initializeDateFormatting`) is bypassed under
  // `flutter test`, so load the date symbols here so the timestamp renders
  // with the resolved locale (en by default).
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('groupChannelMessages', () {
    test('single message is never grouped', () {
      final result = groupChannelMessages([
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
      final result = groupChannelMessages([
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
      // Channels are multi-party: two members could share a display name but
      // never a device fingerprint -- the grouping key is the fingerprint.
      final base = BigInt.from(1700000000000);
      final result = groupChannelMessages([
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
      final result = groupChannelMessages([
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
      final result = groupChannelMessages([
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
      final result = groupChannelMessages([
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
      final result = groupChannelMessages([
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
      final result = groupChannelMessages([
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

  // The widget test drives the screen via a `channelSnapshotProvider`
  // override (the public FutureProvider.family seam) so the controlled
  // messages are deterministic and the FakeGateway / native cdylib are not
  // involved. We seed two peer messages from `bob` (fingerprint `fp-bob`)
  // one minute apart; the second groups under the first, so exactly one
  // sender-meta row should render (device name + fingerprint + HH:mm clock
  // each appearing exactly once for the first message).
  testWidgets('two grouped channel messages render exactly one sender-meta',
      (tester) async {
    const name = 'chan-1';
    final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z
    final snapshot = _snapshot(
      name: name,
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
        channelSnapshotProvider(name).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChannelScreen(name: name),
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
  // `ChannelMessageRow` shows meta unconditionally on non-grouped rows,
  // including the user's own -- `PeerNickname` bolds the own name). The
  // initial port gated meta with `!own && !grouped`, suppressing it on own
  // rows; this test pins the fixed `if (!grouped)` gate.
  testWidgets('own non-grouped channel message renders sender-meta',
      (tester) async {
    const name = 'chan-own';
    final base = BigInt.from(1700000000000);
    final snapshot = _snapshot(
      name: name,
      deviceFingerprint: 'fp-me',
      messages: [
        _msg(
            fromDevice: 'me',
            fromFingerprint: 'fp-me',
            body: 'my own message',
            sentAtMs: base),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        channelSnapshotProvider(name).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChannelScreen(name: name),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('my own message'), findsOneWidget);
    // Own device name renders (was suppressed by the old `!own` gate).
    expect(find.text('me'), findsOneWidget);
    // Own fingerprint renders (channel meta shows the shortened fingerprint).
    expect(find.text('fp-me'), findsOneWidget);
  });

  // Regression: React `ChannelMessageRow` (MessageLists.tsx ~line 378-383)
  // renders name + fingerprint code + timestamp but NO `<MlsBadge />`, while
  // `GroupMessageRow` includes it. The channel meta must therefore NOT
  // render an MLS badge. `MlsBadge` shows the localized "MLS" label
  // (app_en.arb key `mlsBadge` -> "MLS"), so a peer non-grouped channel row
  // must have zero "MLS" text.
  testWidgets('channel peer row omits the MLS badge (React parity)',
      (tester) async {
    const name = 'chan-no-mls';
    final snapshot = _snapshot(
      name: name,
      deviceFingerprint: 'fp-me',
      messages: [
        _msg(
            fromDevice: 'bob',
            fromFingerprint: 'fp-bob',
            body: 'peer msg',
            sentAtMs: BigInt.from(1700000000000)),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        channelSnapshotProvider(name).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChannelScreen(name: name),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('peer msg'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    // No MLS badge on channel rows (React ChannelMessageRow omits it).
    expect(find.text('MLS'), findsNothing);
  });
}
