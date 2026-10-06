import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_ringing.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../../support/voice_call_fakes.dart';

const _incoming = IncomingCallDialog(
    pending: PendingCall(callId: 'first', fromDevice: 'Alice'),
    peerName: 'Alice');
const _outgoing =
    OutgoingCallDialog(call: OutgoingCall(callId: 'second'), peerName: 'Bob');

void main() {
  testWidgets('polls share one ringtone; busy, replacement and end release it',
      (tester) async {
    final player = RecordingRingtone();
    final ringing = CallRinging(player, (_) => fail('unexpected timeout'));
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
  });

  testWidgets(
      'no answer fires once and an unchanged pending snapshot stays silent',
      (tester) async {
    final player = RecordingRingtone();
    final expired = <String>[];
    final ringing = CallRinging(player, expired.add);
    ringing.update(_incoming, busy: false);
    await tester.pump(kIncomingNoAnswerTimeout);
    expect(expired, ['first']);
    expect(player.stops, 1);
    ringing.update(_incoming, busy: false);
    await tester.pump(kIncomingNoAnswerTimeout);
    expect(expired, ['first']);
    expect(player.starts, 1);
    ringing.update(_outgoing, busy: false);
    expect(player.starts, 2);
    ringing.dispose();
  });
}
