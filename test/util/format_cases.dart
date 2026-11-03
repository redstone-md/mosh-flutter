import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show PlatformException;
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
      expect(readableError(FormatException('bad input')),
          'FormatException: bad input');
    });

    test('coerces a non-Error value via toString', () {
      expect(readableError(42), '42');
    });

    test('returns the bare .message for a PlatformException', () {
      expect(
        readableError(
          PlatformException(code: 'x', message: 'BIOMETRIC_UNAVAILABLE: ...'),
        ),
        'BIOMETRIC_UNAVAILABLE: ...',
      );
    });

    test('returns the bare .message for a StateError', () {
      expect(readableError(StateError('foo')), 'foo');
    });

    test('falls back to .toString() for a generic Exception', () {
      // Dart's Exception interface exposes no bare .message, so the
      // fallback yields 'Exception: bar'; assert it is non-empty and
      // contains 'bar' rather than asserting an exact prefix.
      expect(
          readableError(Exception('bar')), allOf(isNotEmpty, contains('bar')));
    });

    test('returns an empty string for a null error', () {
      expect(readableError(null), '');
    });

    test('coerces a plain string via toString', () {
      expect(readableError('plain string'), 'plain string');
    });
  });
}
