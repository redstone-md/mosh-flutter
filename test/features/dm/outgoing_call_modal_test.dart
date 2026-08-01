// Parity tests for `OutgoingCallModal` (lib/src/features/dm/
// outgoing_call_modal.dart) -- the 1-в-1 port of React's
// `OutgoingCallModal.tsx`. Asserts the cancel button + Esc fire onCancel,
// the ringtone starts on mount + stops on dispose, and the peer label +
// "Calling..." status render.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/outgoing_call_modal.dart';
import 'package:mosh/src/features/dm/ringtone_player.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

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

OutgoingCall _outgoing() => const OutgoingCall(callId: 'call-1');

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required OutgoingCallModal modal,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: modal),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cancel button fires onCancel',
    (tester) async {
      var cancelCount = 0;
      await _pump(
        tester,
        modal: OutgoingCallModal(
          call: _outgoing(),
          peerLabel: 'Alice',
          onCancel: () => cancelCount++,
          l: await _l(),
        ),
      );
      await tester.tap(find.byIcon(Icons.phone_disabled));
      expect(cancelCount, 1);
    },
  );

  testWidgets(
    'Esc fires onCancel',
    (tester) async {
      var cancelCount = 0;
      await _pump(
        tester,
        modal: OutgoingCallModal(
          call: _outgoing(),
          peerLabel: 'Alice',
          onCancel: () => cancelCount++,
          l: await _l(),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelCount, 1);
    },
  );

  testWidgets(
    'starts the ringtone on mount and stops it on dispose',
    (tester) async {
      final ringtone = _RecordingRingtonePlayer();
      await _pump(
        tester,
        modal: OutgoingCallModal(
          call: _outgoing(),
          peerLabel: 'Alice',
          onCancel: () {},
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
    'renders the peer label and Calling... status',
    (tester) async {
      await _pump(
        tester,
        modal: OutgoingCallModal(
          call: _outgoing(),
          peerLabel: 'Alice',
          onCancel: () {},
          l: await _l(),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Calling...'), findsOneWidget);
    },
  );

  testWidgets(
    'renders only the cancel button (no accept button)',
    (tester) async {
      await _pump(
        tester,
        modal: OutgoingCallModal(
          call: _outgoing(),
          peerLabel: 'Alice',
          onCancel: () {},
          l: await _l(),
        ),
      );
      expect(find.byIcon(Icons.phone_disabled), findsOneWidget);
      // The outgoing modal has no accept (green phone) button.
      expect(find.byIcon(Icons.phone), findsNothing);
    },
  );
}
