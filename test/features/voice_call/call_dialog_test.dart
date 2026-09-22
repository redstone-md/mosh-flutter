// Unit tests for `callDialogFor` -- the pure snapshot -> dialog derivation.
// No widgets, no timers: a session's call state is a function of its
// snapshot, so asserting it needs nothing but snapshots.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../../support/message_builders.dart';

SessionSnapshot _snapshot({
  PendingCall? pendingCall,
  OutgoingCall? outgoingCall,
  ActiveCall? activeCall,
  String peerDisplayName = 'Alice',
}) =>
    TestSnapshots.dm(
      sessionId: 'sess-1',
      meshId: 'm',
      role: 'caller',
      peerDisplayName: peerDisplayName,
      fingerprint: 'fp',
      pendingCall: pendingCall,
      outgoingCall: outgoingCall,
      activeCall: activeCall,
    );

const _pending = PendingCall(callId: 'call-in', fromDevice: 'Alice');
const _outgoing = OutgoingCall(callId: 'call-out');
final _active = ActiveCall(
  callId: 'call-live',
  direction: 'caller',
  keyB64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  noncePrefixB64: 'AAAAAAAAAAA=',
  startedAtMs: BigInt.from(1000),
);

void main() {
  group('callDialogFor', () {
    test('no snapshot and no call both ask for no dialog', () {
      expect(callDialogFor(null), const NoCallDialog());
      expect(callDialogFor(_snapshot()), const NoCallDialog());
    });

    test('a pending call asks for the incoming modal', () {
      final dialog = callDialogFor(_snapshot(pendingCall: _pending));
      expect(dialog, isA<IncomingCallDialog>());
      expect(dialog.callId, 'call-in');
      expect(dialog.peerName, 'Alice');
      expect((dialog as IncomingCallDialog).pending, _pending);
    });

    test('an outgoing call asks for the outgoing modal', () {
      final dialog = callDialogFor(_snapshot(outgoingCall: _outgoing));
      expect(dialog, isA<OutgoingCallDialog>());
      expect(dialog.callId, 'call-out');
      expect(dialog.peerName, 'Alice');
      expect((dialog as OutgoingCallDialog).call, _outgoing);
    });

    test('an active call asks for the overlay', () {
      final dialog = callDialogFor(_snapshot(activeCall: _active));
      expect(dialog, isA<ActiveCallDialog>());
      expect(dialog.callId, 'call-live');
      expect(dialog.peerName, 'Alice');
      expect((dialog as ActiveCallDialog).active, _active);
    });

    test('a connected call outranks a dialled one', () {
      final dialog = callDialogFor(
        _snapshot(outgoingCall: _outgoing, activeCall: _active),
      );
      expect(dialog, isA<ActiveCallDialog>());
      expect(dialog.callId, 'call-live');
    });

    test('an inbound call outranks the rest', () {
      final dialog = callDialogFor(
        _snapshot(
          pendingCall: _pending,
          outgoingCall: _outgoing,
          activeCall: _active,
        ),
      );
      expect(dialog, isA<IncomingCallDialog>());
      expect(dialog.callId, 'call-in');
    });

    test('an unknown peer name stays empty -- the fallback is the renderer',
        () {
      final incoming = callDialogFor(
        _snapshot(
          pendingCall: const PendingCall(callId: 'c', fromDevice: ''),
        ),
      );
      expect(incoming.peerName, isEmpty);
      final outgoing = callDialogFor(
        _snapshot(outgoingCall: _outgoing, peerDisplayName: ''),
      );
      expect(outgoing.peerName, isEmpty);
    });

    test('an unchanged snapshot derives an equal dialog', () {
      final first = callDialogFor(_snapshot(activeCall: _active));
      final second = callDialogFor(_snapshot(activeCall: _active));
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('a different call is a different dialog', () {
      final first = callDialogFor(_snapshot(activeCall: _active));
      final other = ActiveCall(
        callId: 'call-next',
        direction: 'callee',
        keyB64: _active.keyB64,
        noncePrefixB64: _active.noncePrefixB64,
        startedAtMs: _active.startedAtMs,
      );
      expect(first, isNot(callDialogFor(_snapshot(activeCall: other))));
    });

    test('different shapes never compare equal', () {
      final incoming = callDialogFor(_snapshot(pendingCall: _pending));
      final outgoing = callDialogFor(_snapshot(outgoingCall: _outgoing));
      final active = callDialogFor(_snapshot(activeCall: _active));
      expect(incoming, isNot(outgoing));
      expect(incoming, isNot(active));
      expect(outgoing, isNot(active));
      expect(incoming, isNot(const NoCallDialog()));
    });
  });
}
