import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/system_call_mirror.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

class _Screen implements SystemCallScreen {
  final shown = <String>[];

  @override
  void Function(SystemCallAction action)? onAction;

  @override
  Future<void> show(String callId, SystemCallKind kind, String name) async =>
      shown.add('${kind.name} $callId $name');

  @override
  Future<void> ended(String callId) async => shown.add('ended $callId');
}

IncomingCallDialog incoming(String id, {String name = 'Alice'}) =>
    IncomingCallDialog(
        pending:
            PendingCall(callId: id, fromDevice: name, answerPending: false),
        peerName: name);

OutgoingCallDialog outgoing(String id) =>
    OutgoingCallDialog(call: OutgoingCall(callId: id), peerName: 'Bob');

ActiveCallDialog active(String id) => ActiveCallDialog(
    active:
        ActiveCall(callId: id, direction: 'caller', startedAtMs: BigInt.zero),
    peerName: 'Bob');

void main() {
  late _Screen screen;
  late List<String> app;
  late SystemCallMirror mirror;

  setUp(() {
    screen = _Screen();
    app = [];
    mirror = SystemCallMirror(screen,
        answer: (id) async => app.add('answer $id'),
        end: (id) async => app.add('end $id'),
        mute: (id, muted) => app.add('mute $id $muted'));
  });

  test('a ringing call is shown once and updated when its name arrives', () {
    mirror.show(incoming('c', name: ''));
    mirror.show(incoming('c', name: ''));
    mirror.show(incoming('c'));
    mirror.show(const NoCallDialog());

    expect(screen.shown, ['incoming c ', 'incoming c Alice', 'ended c']);
  });

  test('a call placed in the app goes through the system screen', () {
    mirror.show(outgoing('c'));
    mirror.show(active('c'));
    mirror.show(outgoing('d'));

    expect(screen.shown,
        ['outgoing c Bob', 'active c Bob', 'ended c', 'outgoing d Bob']);
  });

  // A push rings the phone before Moss has delivered the offer; the user may
  // answer or decline in that gap.
  test('an answer given before the offer arrives is applied when it does', () {
    mirror.act(const SystemCallAnswer('c'));
    expect(app, isEmpty);

    mirror.show(incoming('c'));

    expect(app, ['answer c']);
  });

  test('a decline given before the offer arrives ends the call when it does',
      () {
    mirror.act(const SystemCallEnd('c'));
    mirror.show(incoming('c'));

    expect(app, ['end c']);
  });

  test('actions on the shown call reach the app at once', () {
    mirror.show(active('c'));

    mirror.act(const SystemCallMute('c', muted: true));
    mirror.act(const SystemCallEnd('c'));

    expect(app, ['mute c true', 'end c']);
  });
}
