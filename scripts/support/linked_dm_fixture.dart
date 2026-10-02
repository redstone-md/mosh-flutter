import 'dart:async';

import '../../native_test/support/native_peer.dart';

typedef Json = Map<String, dynamic>;

/// Two real public-API installations. The phone is always a third process.
final class LinkedDmFixture {
  LinkedDmFixture(this.original, this.contact, this.invite);

  final NativePeer original;
  final NativePeer contact;
  final Json invite;
  Json? phone;
  String? qr;
  String phase = 'pair';
  String get session => invite['session_id'] as String;

  static Future<LinkedDmFixture> start(String executable) async {
    final original = await NativePeer.start(api: true, executable: executable);
    NativePeer? contact;
    try {
      contact = await NativePeer.start(api: true, executable: executable);
      final invite = await original.ask({'action': 'dm_invite'});
      final fixture = LinkedDmFixture(original, contact, invite);
      await contact
          .ask({'action': 'dm_accept', 'argument': invite['invite_uri']});
      await fixture.waitText(original, 'Before Android pairing', send: true);
      return fixture;
    } catch (_) {
      await Future.wait<void>([
        original.close(),
        if (contact != null) contact.close(),
      ]).catchError((Object _) => <void>[]);
      rethrow;
    }
  }

  Future<Json> waitText(NativePeer peer, String body,
      {bool send = false}) async {
    if (send) {
      await waitFor(
          () => contact.ask({'action': 'dm_poll', 'argument': session}),
          (s) => s['state'] == 'connected',
          'The original DM must connect through automatic Moss discovery');
      await contact
          .ask({'action': 'dm_send', 'argument': session, 'body': body});
    }
    return waitFor(
        () => peer.ask({'action': 'dm_poll', 'argument': session}),
        (s) => (s['messages'] as List).any((m) => m['body'] == body),
        'The real desktop must receive $body');
  }

  Future<Json> handle(String action, Json data) async {
    switch (action) {
      case 'state':
        return {
          'session': session,
          'fingerprint': invite['fingerprint'],
          'phase': phase,
          'phone': phone,
        };
      case 'peer':
        final peer = switch (data.remove('target')) {
          'original' => original,
          'contact' => contact,
          _ => throw const FormatException('Unknown fixture installation'),
        };
        final result = await peer.ask(data);
        if (data['action'] == 'qr') qr = result['qr_uri'] as String;
        return result;
      case 'save-phone':
        phone = data;
        return {};
      case 'stop-original':
        await original.stop();
        return {};
      case 'restart-original':
        await original.restart();
        await waitText(original, 'Phone without desktop');
        await waitText(original, 'Contact without desktop');
        return {};
      case 'wait-text':
        return waitText(data['target'] == 'original' ? original : contact,
            data['body'] as String);
      case 'revoke':
        return original.ask({'action': 'revoke', 'argument': data['device']});
      case 'old-qr':
        return {'uri': qr};
      default:
        throw const FormatException('Unknown fixture operation');
    }
  }

  Future<void> beforeColdStart() async {
    phase = 'restore';
    await waitText(original, 'While Android stopped', send: true);
  }

  Future<void> close() =>
      Future.wait<void>([original.close(), contact.close()]);
}

Future<Json> waitFor(Future<Json> Function() read, bool Function(Json) ready,
    String failure) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final value = await read();
    if (ready(value)) return value;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(failure);
}
