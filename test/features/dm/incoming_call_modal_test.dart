// Parity tests for `IncomingCallModal` (lib/src/features/dm/
// incoming_call_modal.dart) -- the 1-в-1 port of React's
// `IncomingCallModal.tsx`. Asserts the accept/decline buttons fire the
// right callbacks, Esc maps to the user-decline reason, the no-answer
// timer fires `'no_answer'`, and the ringtone is started on mount +
// stopped on dispose.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/incoming_call_modal.dart';
import 'package:mosh/src/features/dm/ringtone_player.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import '../../support/pump.dart';

/// A [RingtonePlayer] that records start/stop calls so the tests can
/// assert the ringtone lifecycle without an audio backend.
class _RecordingRingtonePlayer implements RingtonePlayer {
  int startCount = 0;
  int stopCount = 0;
  @override
  RingtoneHandle start() {
    startCount++;
    return _RecordingHandle(this);
  }
}

class _RecordingHandle implements RingtoneHandle {
  _RecordingHandle(this.player);
  final _RecordingRingtonePlayer player;
  @override
  void stop() => player.stopCount++;
}

class _FailingRingtonePlayer implements RingtonePlayer {
  @override
  RingtoneHandle start() => throw StateError('no output device');
}

PendingCall _pending() => const PendingCall(
      callId: 'call-1',
      fromDevice: 'peer-device',
    );

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required IncomingCallModal modal,
}) =>
    pumpScreen(tester, Scaffold(body: modal));

void main() {
  testWidgets(
    'accept button fires onAccept',
    (tester) async {
      var acceptCount = 0;
      await _pump(
        tester,
        modal: IncomingCallModal(
          pending: _pending(),
          peerLabel: 'Alice',
          onAccept: () => acceptCount++,
          onDecline: (_) {},
          l: await _l(),
        ),
      );
      await tester.tap(find.byIcon(Icons.phone));
      expect(acceptCount, 1);
    },
  );

  testWidgets(
    'decline button fires onDecline with the user reason',
    (tester) async {
      String? reason;
      await _pump(
        tester,
        modal: IncomingCallModal(
          pending: _pending(),
          peerLabel: 'Alice',
          onAccept: () {},
          onDecline: (r) => reason = r,
          l: await _l(),
        ),
      );
      await tester.tap(find.byIcon(Icons.phone_disabled));
      expect(reason, kCallDeclineReasonUser);
    },
  );

  testWidgets(
    'Esc fires onDecline with the user reason',
    (tester) async {
      String? reason;
      await _pump(
        tester,
        modal: IncomingCallModal(
          pending: _pending(),
          peerLabel: 'Alice',
          onAccept: () {},
          onDecline: (r) => reason = r,
          l: await _l(),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(reason, kCallDeclineReasonUser);
    },
  );

  testWidgets(
    'no-answer timeout fires onDecline with the no_answer reason',
    (tester) async {
      String? reason;
      await _pump(
        tester,
        modal: IncomingCallModal(
          pending: _pending(),
          peerLabel: 'Alice',
          onAccept: () {},
          onDecline: (r) => reason = r,
          noAnswerTimeout: const Duration(milliseconds: 100),
          l: await _l(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(reason, kCallDeclineReasonNoAnswer);
    },
  );

  testWidgets(
    'starts the ringtone on mount and stops it on dispose',
    (tester) async {
      final ringtone = _RecordingRingtonePlayer();
      await _pump(
        tester,
        modal: IncomingCallModal(
          pending: _pending(),
          peerLabel: 'Alice',
          onAccept: () {},
          onDecline: (_) {},
          ringtone: ringtone,
          l: await _l(),
        ),
      );
      expect(ringtone.startCount, 1);
      expect(ringtone.stopCount, 0);
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
      expect(ringtone.stopCount, 1);
    },
  );

  testWidgets(
    'keeps the modal alive when the ringtone device is unavailable',
    (tester) async {
      await _pump(
        tester,
        modal: IncomingCallModal(
          pending: _pending(),
          peerLabel: 'Alice',
          onAccept: () {},
          onDecline: (_) {},
          ringtone: _FailingRingtonePlayer(),
          l: await _l(),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Incoming voice call...'), findsOneWidget);
    },
  );

  testWidgets(
    'renders the peer label and localized status',
    (tester) async {
      await _pump(
        tester,
        modal: IncomingCallModal(
          pending: _pending(),
          peerLabel: 'Alice',
          onAccept: () {},
          onDecline: (_) {},
          l: await _l(),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Incoming voice call...'), findsOneWidget);
    },
  );
}
