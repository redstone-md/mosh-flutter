// Unit tests for `formatBytes(BigInt)` in lib/src/util/format.dart:
// < 1024 -> "{n} B"; otherwise divide by 1024 through KB/MB/GB with
// `value >= 10 ? 0 : 1` decimal places. Uses `BigInt.from` since the
// contract's `totalSize` is a `BigInt`.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/util/format.dart';

void main() {
  group('formatBytes', () {
    test('0 B', () {
      expect(formatBytes(BigInt.from(0)), '0 B');
    });

    test('512 B (under 1024 keeps raw bytes)', () {
      expect(formatBytes(BigInt.from(512)), '512 B');
    });

    test('1023 B (just under the KB boundary)', () {
      expect(formatBytes(BigInt.from(1023)), '1023 B');
    });

    test('1024 -> "1.0 KB" (exactly 1 KB, one decimal)', () {
      expect(formatBytes(BigInt.from(1024)), '1.0 KB');
    });

    test('1536 -> "1.5 KB"', () {
      expect(formatBytes(BigInt.from(1536)), '1.5 KB');
    });

    test('1048576 -> "1.0 MB"', () {
      expect(formatBytes(BigInt.from(1048576)), '1.0 MB');
    });

    test('1572864 -> "1.5 MB"', () {
      expect(formatBytes(BigInt.from(1572864)), '1.5 MB');
    });

    test('1073741824 -> "1.0 GB"', () {
      expect(formatBytes(BigInt.from(1073741824)), '1.0 GB');
    });

    test('10485760 (10 MB) -> "10 MB" (>= 10 drops the decimal)', () {
      expect(formatBytes(BigInt.from(10485760)), '10 MB');
    });

    test('15728640 (15 MB) -> "15 MB" (>= 10 drops the decimal)', () {
      expect(formatBytes(BigInt.from(15728640)), '15 MB');
    });

    test('5120 KB (5 MB) keeps one decimal (value < 10)', () {
      // 5 * 1024 * 1024 = 5242880 bytes -> 5.0 MB
      expect(formatBytes(BigInt.from(5242880)), '5.0 MB');
    });
  });
}
