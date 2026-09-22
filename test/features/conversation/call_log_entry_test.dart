// Tests for `CallLogEntry` (lib/src/features/conversation/call_log_entry.dart).
// Asserts the missed and completed variants render the right icon + localized
// label, and that a non-zero duration appends ` · m:ss`; zero duration omits
// the suffix.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/call_log_entry.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import '../../support/pump.dart';

Future<void> _pump(WidgetTester tester, CallLogEntry card) =>
    pumpScreen(tester, Scaffold(body: Center(child: card)));

CallEvent _event({required String kind, required int durationMs}) => CallEvent(
      kind: kind,
      durationMs: BigInt.from(durationMs),
      callId: 'call-1',
    );

void main() {
  testWidgets(
    'missed call renders the phone-off icon + Missed call label',
    (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(
        tester,
        CallLogEntry(event: _event(kind: 'missed', durationMs: 0), l: l),
      );
      expect(find.byIcon(Icons.phone_disabled), findsOneWidget);
      expect(find.text('Missed call'), findsOneWidget);
      expect(find.byIcon(Icons.phone), findsNothing);
    },
  );

  testWidgets(
    'completed call renders the phone icon + Call ended label',
    (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(
        tester,
        CallLogEntry(event: _event(kind: 'completed', durationMs: 0), l: l),
      );
      expect(find.byIcon(Icons.phone), findsOneWidget);
      expect(find.text('Call ended'), findsOneWidget);
      expect(find.byIcon(Icons.phone_disabled), findsNothing);
    },
  );

  testWidgets(
    'a non-zero duration appends · m:ss with zero-padded seconds',
    (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      // 65000 ms -> 1:05.
      await _pump(
        tester,
        CallLogEntry(
          event: _event(kind: 'completed', durationMs: 65000),
          l: l,
        ),
      );
      expect(find.text('Call ended · 1:05'), findsOneWidget);
    },
  );

  testWidgets(
    'a zero duration omits the duration suffix',
    (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(
        tester,
        CallLogEntry(event: _event(kind: 'missed', durationMs: 0), l: l),
      );
      // Missed with 0 ms -> no suffix, just "Missed call".
      expect(find.text('Missed call'), findsOneWidget);
      // A zero-duration entry must not contain the middle-dot separator.
      expect(find.textContaining(' · '), findsNothing);
    },
  );

  test('formatCallDuration renders duration text', () {
    expect(formatCallDuration(BigInt.zero), '');
    expect(formatCallDuration(BigInt.from(999)), '');
    expect(formatCallDuration(BigInt.from(1000)), '0:01');
    expect(formatCallDuration(BigInt.from(65000)), '1:05');
    expect(formatCallDuration(BigInt.from(3661000)), '61:01');
  });
}
