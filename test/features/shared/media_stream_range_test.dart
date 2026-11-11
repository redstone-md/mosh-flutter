// ignore_for_file: depend_on_referenced_packages
import 'package:test/test.dart';
import 'package:mosh/src/features/shared/media_stream_server.dart';

void main() {
  group('parseMediaRange', () {
    test('defaults to the whole attachment', () {
      final range = parseMediaRange(null)!;
      expect(range.start, BigInt.zero);
      expect(range.end, isNull);
      expect(range.endExclusive(BigInt.from(700000)), BigInt.from(700000));
    });

    test('parses normal and open-ended ranges', () {
      final normal = parseMediaRange('bytes=10-20')!;
      expect(normal.start, BigInt.from(10));
      expect(normal.end, BigInt.from(20));
      expect(normal.endExclusive(BigInt.from(100)), BigInt.from(21));

      final open = parseMediaRange(' bytes=10- ')!;
      expect(open.end, isNull);
      expect(open.endExclusive(BigInt.from(100)), BigInt.from(100));
    });

    test('a range past the attachment\'s end stops at it', () {
      final range = parseMediaRange('bytes=0-999999')!;
      expect(range.endExclusive(BigInt.from(1000)), BigInt.from(1000));
    });

    test(
        'rejects malformed, multiple, suffix, reversed, and overflowing ranges',
        () {
      for (final value in <String?>[
        'bytes=abc-10',
        'bytes=1-2,3-4',
        'bytes=-10',
        'bytes=20-10',
        'bytes=18446744073709551616-',
        'bytes=0-18446744073709551616',
      ]) {
        expect(parseMediaRange(value), isNull, reason: value);
      }
    });
  });

  group('MediaStreamRoute', () {
    test('accepts all conversation kinds and decodes path segments', () {
      for (final kind in <String>['dm', 'channel', 'group']) {
        final uri = Uri.parse(
          'http://127.0.0.1/$kind/host%20with%20space/att%2F1',
        );
        final route = MediaStreamRoute.parse(uri)!;
        expect(route.kind, kind);
        expect(route.host, 'host with space');
        expect(route.attachmentId, 'att/1');
      }
    });

    test('rejects unknown and malformed routes', () {
      expect(MediaStreamRoute.parse(Uri.parse('http://x/mesh/h/a')), isNull);
      expect(MediaStreamRoute.parse(Uri.parse('http://x/dm/h')), isNull);
      expect(
          MediaStreamRoute.parse(Uri.parse('http://x/dm/h/a/extra')), isNull);
      expect(MediaStreamRoute.parse(Uri.parse('http://x/dm//a')), isNull);
    });
  });
}
