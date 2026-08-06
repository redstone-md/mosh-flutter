// Unit tests for [peerLabel] -- the Flutter port of React's `peerLabel`
// (mosh/src/features/private-dm/private-dm-screen.tsx:535-543). Pure
// function; no widget pump. Uses the generated `lookupAppLocalizations`
// singleton (en) for the localized "Peer"/"invite sent"/"joining" strings
// so the test stays hermetic without a MaterialApp harness.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/peer_label.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

ChatMessage _msg(String fromDevice) =>
    ChatMessage(fromDevice: fromDevice, body: 'x');

SessionSnapshot _session({
  required String role,
  required String state,
  String peerDisplayName = '',
  String displayName = 'me',
  List<ChatMessage> messages = const [],
}) =>
    SessionSnapshot(
      sessionId: 's1',
      meshId: 'm1',
      role: role,
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      path: 'direct',
      fingerprint: 'fp',
      messages: messages,
      attachments: const [],
      events: const [],
    );

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  group('peerLabel', () {
    test('populated peerDisplayName short-circuits (Flutter optimization)', () {
      final s = _session(
        role: 'alice',
        state: 'pending',
        peerDisplayName: 'remote-pal',
      );
      expect(peerLabel(l, s), 'remote-pal');
    });

    test('empty peerDisplayName + a peer message -> that fromDevice (React primary branch)', () {
      final s = _session(
        role: 'alice',
        state: 'pending',
        messages: [_msg('me'), _msg('remote-peer'), _msg('me')],
      );
      expect(peerLabel(l, s), 'remote-peer');
    });

    test('empty + no peer message + state==ready -> "Peer" (callPeerFallback)', () {
      final s = _session(role: 'alice', state: 'ready', messages: [_msg('me')]);
      expect(peerLabel(l, s), l.callPeerFallback);
    });

    test('empty + not ready + role==alice -> "invite sent"', () {
      final s = _session(role: 'alice', state: 'pending', messages: [_msg('me')]);
      expect(peerLabel(l, s), 'invite sent');
    });

    test('empty + not ready + role==bob -> "joining"', () {
      final s = _session(role: 'bob', state: 'pending', messages: [_msg('me')]);
      expect(peerLabel(l, s), 'joining');
    });

    test('messages from own display_name are skipped, not treated as peer', () {
      // React: messages.find(m => m.from_device !== session.display_name).
      final s = _session(
        role: 'alice',
        state: 'pending',
        messages: [_msg('me'), _msg('me')],
      );
      // No peer message + not ready + alice -> invite sent.
      expect(peerLabel(l, s), 'invite sent');
    });
  });
}
