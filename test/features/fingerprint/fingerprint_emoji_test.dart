// Unit tests for the emoji fingerprint mapping: determinism, the
// known vectors (computed against the same rules as the implementation,
// not from it), the empty/short edge cases, and the hex/non-hex byte
// sources. See fingerprint-lock.plan.md step 3.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';

void main() {
  test('empty fingerprint renders no emoji', () {
    expect(fingerprintEmoji(''), isEmpty);
  });

  test('a non-empty fingerprint renders exactly four emoji', () {
    expect(fingerprintEmoji('0011223344556677'), hasLength(4));
    expect(fingerprintEmoji('fp-peer-1234'), hasLength(4));
    expect(fingerprintEmoji('a'), hasLength(4));
  });

  test('the same fingerprint always maps to the same emoji', () {
    expect(fingerprintEmoji('0011223344556677'),
        equals(fingerprintEmoji('0011223344556677')));
  });

  test('known vector: hex bytes map to their pool slots', () {
    // Bytes 00 11 22 33 44 55 66 77 -> pairs 0x0011=17, 0x2233=8755,
    // 0x4455=17493, 0x6677=26231 -> pool slots 17, 97, 177, 257 of the
    // Telegram pool (pool size 333).
    expect(fingerprintEmoji('0011223344556677'), [
      '\ud83d\udc68', // pool[17]
      '\ud83d\udc3c', // pool[97]
      '\ud83d\udcb0', // pool[177]
      '\ud83c\udf45', // pool[257]
    ]);
  });

  test('known vector: non-hex seed strings fall back to code units', () {
    expect(fingerprintEmoji('fp-peer-1234'), [
      '\ud83c\udf49', // (f, p) -> 26224 % 333 = 250
      '\ud83c\uddec\ud83c\udde7', // (-, e) -> 11565 % 333 = 34
      '\u0036\u20e3', // (r, -) -> 29229 % 333 = 264
      '\ud83c\udf3d', // (p, e) -> 28773 % 333 = 291
    ]);
  });

  test('a one-byte change moves the quartet', () {
    expect(
      fingerprintEmoji('deadbeefdeadbeef'),
      isNot(equals(fingerprintEmoji('deadbeefdeadbeee'))),
    );
  });

  test('an odd-length single char falls back to code units and wraps', () {
    expect(fingerprintEmoji('a'), [
      '\ud83d\ude94',
      '\ud83d\ude94',
      '\ud83d\ude94',
      '\ud83d\ude94',
    ]);
  });

  test('hex letter case does not change the mapping', () {
    expect(fingerprintEmoji('ffffffffffffffff'),
        equals(fingerprintEmoji('FFFFFFFFFFFFFFFF')));
  });
}
