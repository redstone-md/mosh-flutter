// Unit + widget tests for the locale-aware message timestamp:
// `formatClock` (the visible HH:mm) and `formatClockFull` (the full
// date-time tooltip), both in the LOCAL timezone and driven by the
// AppLocalizations locale via `intl`'s `DateFormat`. The widget test
// pumps `DmScreen` with one non-grouped peer message carrying a fixed
// epoch and asserts the visible HH:mm renders AND a `Tooltip` with the
// full locale-aware date-time message is present.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/state/session_providers.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';

void main() {
  // `initializeDateFormatting` is required for non-en locale symbols; the
  // widget test below drives `SenderMeta` through DmScreen, and `main()` is
  // bypassed under `flutter test` (see widget_test.dart limitation). Calling
  // it in setUpAll keeps the en default loaded (it ships pre-loaded) and
  // makes the suite safe if a ru-locale test is added later.
  setUpAll(() async {
    await initializeDateFormatting();
  });

  // Fixed epoch used across the unit + widget assertions so the expected
  // strings can be derived from the same value deterministically.
  const ms = 1700000000000; // 2023-11-14T22:13:20Z
  final epoch = BigInt.from(ms);

  // Expected strings are computed LAZILY inside each test (not as top-level
  // field initializers) because `DateFormat.Hm('en')` requires the intl
  // date symbols to be loaded, and `setUpAll` runs AFTER top-level
  // initialization. Computing them in-test keeps the unit tests (which do
  // not pump a localized MaterialApp) safe.
  String expectedClock() => DateFormat.Hm('en')
      .format(DateTime.fromMillisecondsSinceEpoch(ms).toLocal());

  String expectedFull() => DateFormat.yMMMd('en')
      .add_Hm()
      .format(DateTime.fromMillisecondsSinceEpoch(ms).toLocal());

  group('formatClock', () {
    test('returns the locale-aware local-time HH:mm for a fixed epoch', () {
      final clock = formatClock(epoch, locale: 'en');
      expect(clock, isNotNull);
      expect(clock, expectedClock());
      // HH:mm is exactly 5 chars in the en locale (24h "HH:mm").
      expect(clock!.length, 5);
    });

    test('returns null when sentAtMs is null', () {
      expect(formatClock(null, locale: 'en'), isNull);
    });
  });

  group('formatClockFull', () {
    test('returns a non-null full date-time containing the year + a time', () {
      final full = formatClockFull(epoch, locale: 'en');
      expect(full, isNotNull);
      // The full string embeds the year.
      expect(full, contains('2023'));
      // And it is strictly longer than the HH:mm clock.
      expect(full!.length, greaterThan(expectedClock().length));
    });

    test('returns null when sentAtMs is null', () {
      expect(formatClockFull(null, locale: 'en'), isNull);
    });
  });

  group('SenderMeta timestamp', () {
    const sessionId = 'sess-ts';

    testWidgets('renders the visible HH:mm + a Tooltip with the full date-time',
        (tester) async {
      final snapshot = TestSnapshots.dm(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          TestMessages.dm(fromDevice: 'bob', body: 'first', sentAtMs: epoch),
        ],
      );

      await pumpScreen(tester, const DmScreen(sessionId: sessionId),
          overrides: [
            activeSessionProvider(sessionId)
                .overrideWith((ref) async => snapshot),
          ]);

      // The visible locale-aware HH:mm renders.
      expect(find.text(expectedClock()), findsOneWidget);

      // A Tooltip carrying the full locale-aware date-time is present.
      // The DM meta row also has the MlsBadge Tooltip, so we match by
      // message rather than by type alone.
      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
      final expected = expectedFull();
      final timestampTooltip = tooltips.firstWhere(
        (t) => t.message == expected,
        orElse: () => fail('No Tooltip with the full date-time message '
            '"$expected" found. Tooltip messages: '
            '${tooltips.map((t) => t.message).toList()}'),
      );
      expect(timestampTooltip.message, expected);
    });
  });
}
