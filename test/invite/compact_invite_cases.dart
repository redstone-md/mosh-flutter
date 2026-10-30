import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/invite/invite_detection.dart';
import 'package:mosh/src/invite/invite_uri.dart';

// Flutter checks routing shape. Rust verifies both signatures before admission.
String _invite({int flags = 2, int version = 1, int? length}) {
  final bytes = Uint8List(
    length ?? 210 + ((flags & 2) != 0 ? 8 : 0) + ((flags & 1) != 0 ? 32 : 0),
  );
  bytes[0] = version;
  bytes[1] = flags;
  for (var i = 2; i < 82 && i < bytes.length; i++) {
    bytes[i] = i;
  }
  return 'mosh://invite/${base64Url.encode(bytes).replaceAll('=', '')}';
}

void main() {
  test(
    'compact invitation extracts stable route and the creator fingerprint',
    () {
      final raw = _invite();
      final invite = parseMoshInvite(raw);
      expect(invite.meshId, 'mesh-0203040506070809');
      expect(invite.sessionId, 'session-0a0b0c0d0e0f1011');
      expect(invite.fingerprint, '32333435363738393A3B3C3D3E3F4041');
      expect(invite.peerHint, isNull);
      expect(detectInvite(raw).kind, InviteDetectionKind.dm);
      expect(detectInvite('  $raw\n').kind, InviteDetectionKind.dm);
    },
  );

  test('targeted and unrotated compact invitations are detected', () {
    for (final flags in [0, 1, 2, 3]) {
      expect(detectInvite(_invite(flags: flags)).kind, InviteDetectionKind.dm);
    }
  });

  test('malformed compact payloads and appended fields are rejected', () {
    for (final raw in [
      _invite(version: 2),
      _invite(flags: 4),
      _invite(length: 210),
      _invite(length: 219),
      'mosh://invite/!bad',
      'mosh://invite/AA',
      '${_invite()}=',
      '${_invite()}?target=bad',
      '${_invite()}#fp=bad',
      '${_invite()}/',
    ]) {
      expect(
        () => parseMoshInvite(raw),
        throwsA(isA<InviteParseError>()),
        reason: raw,
      );
      expect(detectInvite(raw).kind, InviteDetectionKind.unknown);
    }
  });
}
