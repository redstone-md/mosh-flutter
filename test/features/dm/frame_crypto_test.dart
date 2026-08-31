// Parity tests for `frame_crypto` (lib/src/features/dm/frame_crypto.dart) --
// the 1-to-1 port of the AES-GCM seal/open surface from React
// `src/features/private-dm/voice-call/frame-crypto.ts`. The pure helpers
// (buildFrame / parseFrame / direction bits) are covered separately by
// `frame_codec_test.dart`.
// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/frame_codec.dart';
import 'package:mosh/src/features/dm/frame_crypto.dart';

const String KEY_B64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; // 32 zero bytes
const String PREFIX_B64 = 'AAAAAA=='; // 4 zero bytes

void main() {
  group('frame_crypto', () {
    test('seals and opens a frame with the same key', () async {
      final key = await importCallKey(KEY_B64);
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sealed = await sealFrame(
          key, PREFIX_B64, BigInt.from(7), CALLER_DIRECTION_BIT, payload);
      final opened = await openFrame(key, PREFIX_B64, sealed);
      expect(opened, isNotNull);
      expect(opened!.payload, [1, 2, 3, 4, 5]);
      expect(opened.seq, BigInt.from(7));
    });

    test('rejects a tampered frame', () async {
      final key = await importCallKey(KEY_B64);
      final sealed = await sealFrame(
        key,
        PREFIX_B64,
        BigInt.from(1),
        CALLER_DIRECTION_BIT,
        Uint8List.fromList([9, 9, 9]),
      );
      sealed[sealed.length - 1] ^= 0xff;
      final opened = await openFrame(key, PREFIX_B64, sealed);
      expect(opened, isNull);
    });

    test(
        'rejects a seq that would overflow the 63-bit value space (no silent wrap)',
        () async {
      final key = await importCallKey(KEY_B64);
      // 2^63 masks down to 0 -- sealing it would silently reuse seq 0's nonce.
      expect(
        () => sealFrame(key, PREFIX_B64, BigInt.one << 63, CALLER_DIRECTION_BIT,
            Uint8List.fromList([1])),
        throwsArgumentError,
      );
      expect(
        () => sealFrame(key, PREFIX_B64, BigInt.from(-1), CALLER_DIRECTION_BIT,
            Uint8List.fromList([1])),
        throwsArgumentError,
      );
    });
  });
}
