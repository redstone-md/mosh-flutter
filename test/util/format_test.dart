import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/util/format.dart';

void main() {
  group('shorten', () {
    test('returns an em dash for an empty value', () {
      expect(shorten('', 4), '—');
    });

    test('returns the value unchanged when short enough', () {
      // length 9 <= 4 * 2 + 1 = 9, boundary inclusive (mirrors TS `<=`)
      expect(shorten('abcdefghi', 4), 'abcdefghi');
    });

    test('ellipsizes long values to head…tail form', () {
      // length 17 > 9 -> head 4 chars + '…' + last 4 chars
      expect(shorten('abcdefghijklmnopq', 4), 'abcd…nopq');
    });
  });

  group('readableError', () {
    test('renders a Dart error via its message', () {
      expect(readableError(FormatException('bad input')), 'FormatException: bad input');
    });

    test('coerces a non-Error value via toString', () {
      expect(readableError(42), '42');
    });
  });
}
