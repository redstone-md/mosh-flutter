// Parity tests for `frame_codec` (lib/src/features/voice_call/frame_codec.dart) --
// the 1-to-1 port of the pure helpers from React
// `src/features/private-dm/voice-call/frame-crypto.ts`. Covers only the
// non-crypto helpers; the AES-GCM seal/open + key import are skipped (crypto
// package TBD).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/frame_codec.dart';

void main() {
  group('frame_codec', () {
    test('buildFrame and parseFrame roundtrip the seq', () {
      final wire = buildFrame(BigInt.from(42), Uint8List.fromList([1, 2, 3]));
      final parsed = parseFrame(wire);
      expect(parsed, isNotNull);
      expect(parsed!.seq, BigInt.from(42));
      expect(parsed.ciphertext, Uint8List.fromList([1, 2, 3]));
    });

    test('CALLER and CALLEE direction bits differ', () {
      expect(CALLER_DIRECTION_BIT, isNot(CALLEE_DIRECTION_BIT));
    });

    test('parseFrame returns null for a too-short frame', () {
      expect(parseFrame(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])), isNull);
    });

    test('buildNonce produces a 12-byte nonce with prefix then BE seq', () {
      final nonce = buildNonce('AAAAAA==', BigInt.from(7));
      expect(nonce.length, 12);
      expect(nonce.sublist(0, 4), bytesFromBase64('AAAAAA=='));
      expect(nonce.sublist(4, 12), seqToBytes(BigInt.from(7)));
    });

    test('buildNonce throws when prefix is not 4 bytes', () {
      expect(() => buildNonce('AA==', BigInt.zero), throwsArgumentError);
      expect(() => buildNonce('AAAA', BigInt.zero), throwsArgumentError);
    });

    test('seqToBytes and bytesToSeq roundtrip', () {
      final cases = <BigInt>[
        BigInt.zero,
        BigInt.from(42),
        BigInt.from(0x12345678),
        CALLEE_DIRECTION_BIT,
        BigInt.two.pow(64) - BigInt.one,
      ];
      for (final s in cases) {
        expect(bytesToSeq(seqToBytes(s), 0), s, reason: 'seq=$s');
      }
    });

    test('CALLEE_DIRECTION_BIT has bit 63 set', () {
      expect(CALLEE_DIRECTION_BIT >> 63, BigInt.one);
      expect(seqToBytes(CALLEE_DIRECTION_BIT)[0] & 0x80, 0x80);
    });
  });
}
