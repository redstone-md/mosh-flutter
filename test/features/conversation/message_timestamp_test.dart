// Unit + widget tests for the locale-aware message timestamp:
// `formatClock` (the visible HH:mm) and `formatClockFull` (the full
// date-time tooltip), both in the LOCAL timezone. The widget test pumps
// `DmScreen` with one non-grouped peer message and asserts the visible
// HH:mm renders AND a `Tooltip` with the full date-time is present.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/state/session_providers.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';

void main() {
  // `main()` is bypassed under `flutter test`, so load the intl date
  // symbols here.
  setUpAll(() async {
    await initializeDateFormatting();
  });

  // A local wall-clock time, so the expected strings hold in any timezone.
  final epoch =
      BigInt.from(DateTime(2023, 11, 14, 9, 5).millisecondsSinceEpoch);
  const clock = '09:05';
  const full = 'Nov 14, 2023 09:05';

  group('formatClock', () {
    test('returns the zero-padded 24-hour local time', () {
      expect(formatClock(epoch, locale: 'en'), clock);
    });

    test('returns null when sentAtMs is null', () {
      expect(formatClock(null, locale: 'en'), isNull);
    });
  });

  group('formatClockFull', () {
    test('returns the local date and 24-hour time', () {
      expect(formatClockFull(epoch, locale: 'en'), full);
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

      expect(find.text(clock), findsOneWidget);
      expect(find.byTooltip(full), findsOneWidget);
    });
  });
}
