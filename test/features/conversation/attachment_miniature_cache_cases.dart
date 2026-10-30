import 'dart:convert' show base64Encode;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/conversation/attachment_preview_image.dart';

String miniature(int width, int height) =>
    base64Encode(img.encodePng(img.Image(width: width, height: height)));

String wideText(int length) => String.fromCharCodes(List.filled(length, 0x100));

void main() {
  test('an oversized malformed key cannot displace reusable miniatures', () {
    final source = miniature(48, 32);
    final first = decodeMiniature(source);
    expect(first.size, const Size(48, 32));
    final wide = wideText(65536);
    for (var index = 0; index < 70; index++) {
      final malformed = decodeMiniature('$wide$index');
      expect(malformed.bytes, isEmpty);
      expect(malformed.size, isNull);
    }
    expect(identical(decodeMiniature(source).bytes, first.bytes), isTrue);
  });

  test('the total payload budget includes two-byte malformed keys', () {
    final source = miniature(49, 31);
    final first = decodeMiniature(source);
    final wide = wideText(4096);
    for (var index = 0; index < 520; index++) {
      expect(decodeMiniature('$wide$index').bytes, isEmpty);
    }
    final refreshed = decodeMiniature(source);
    expect(identical(refreshed.bytes, first.bytes), isFalse);
    expect(refreshed.bytes, first.bytes);
    expect(refreshed.size, const Size(49, 31));
  });

  test('large valid thumbnails decode without being retained', () {
    final source = base64Encode(Uint8List(150 * 1024));
    final first = decodeMiniature(source);
    final next = decodeMiniature(source);
    expect(first.bytes.length, 150 * 1024);
    expect(next.bytes, first.bytes);
    expect(identical(next.bytes, first.bytes), isFalse);
  });
}
