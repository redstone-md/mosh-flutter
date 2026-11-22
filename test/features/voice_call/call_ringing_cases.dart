import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_ringing.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../../support/voice_call_fakes.dart';

const _incoming = IncomingCallDialog(
    pending:
        PendingCall(answerPending: false, callId: 'first', fromDevice: 'Alice'),
    peerName: 'Alice');
const _outgoing =
    OutgoingCallDialog(call: OutgoingCall(callId: 'second'), peerName: 'Bob');

void main() {
  testWidgets('polls share one ringtone; busy, replacement and end release it',
      (tester) async {
    final player = RecordingRingtone();
    final ringing = CallRinging(player);
    ringing.update(_incoming, busy: false);
    ringing.update(_incoming, busy: false);
    expect(player.starts, 1);
    ringing.update(_incoming, busy: true);
    expect(player.stops, 1);
    ringing.update(_incoming, busy: false);
    expect(player.starts, 2);
    ringing.update(_outgoing, busy: false);
    expect(player.stops, 2);
    expect(player.starts, 3);
    ringing.update(const NoCallDialog(), busy: false);
    expect(player.stops, 3);
    ringing.dispose();
    expect(player.stops, 3);
    expect(player.kinds,
        [RingtoneKind.incoming, RingtoneKind.incoming, RingtoneKind.outgoing],
        reason: 'each direction plays its own ringtone');
  });

  testWidgets('a phone that rings incoming calls itself plays only outgoing',
      (tester) async {
    final player = RecordingRingtone();
    final ringing = CallRinging(player, incomingManaged: true);
    ringing.update(_incoming, busy: false);
    expect(player.starts, 0);
    ringing.update(_outgoing, busy: false);
    expect(player.kinds, [RingtoneKind.outgoing]);
    ringing.dispose();
    expect(player.stops, 1);
  });

  test('a ringtone that cannot play leaves the call usable', () {
    final ringing = CallRinging(_SilentOutput());
    expect(() => ringing.update(_incoming, busy: false), returnsNormally);
    ringing.dispose();
  });
}

/// An output device that refuses to play.
class _SilentOutput implements RingtonePlayer {
  @override
  RingtoneHandle start(RingtoneKind kind) =>
      throw StateError('no output device');
}
