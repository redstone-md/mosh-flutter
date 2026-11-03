// Unit tests for the shared `createThumbnail` helper
// (lib/src/features/shared/thumbnail.dart). We synthesize a tiny PNG
// in-memory via the same `image` package the helper uses (so the test
// needs no fixture file), then assert:
//   - a PNG image pick -> a non-null base64 JPEG string (the 320px preview)
//   - a non-image (mime not image/*) -> null
//   - a corrupt .png (random bytes) -> null

import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/shared/thumbnail.dart';

Uint8List _png(int width, int height, int rgb) {
  final image = img.Image(width: width, height: height);
  img.fill(image,
      color: img.ColorRgb8((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('createThumbnail', () {
    test('returns a base64 JPEG for an image pick', () async {
      // A 100x80 PNG larger than the test default; the helper should resize
      // to the 320px max-edge (here the width 100 < 320, so no upscale --
      // the scale clamps at 1). The output is a JPEG base64.
      final bytes = _png(100, 80, 0xFFAABBCC);
      final result = await createThumbnail(bytes, 'pick.png');
      expect(result, isNotNull);
      // Decoding the base64 must yield JPEG magic bytes (FF D8 FF).
      final jpeg = base64Decode(result!);
      expect(jpeg[0], 0xFF);
      expect(jpeg[1], 0xD8);
      expect(jpeg[2], 0xFF);
    });

    test('resizes a large image to the 320px max-edge', () async {
      // A 800x600 image: the longest edge is 800, so the thumbnail should be
      // 320x240 (320 * 600/800 = 240). Decode the JPEG and assert dimensions.
      final bytes = _png(800, 600, 0xFF0000FF);
      final result = await createThumbnail(bytes, 'big.png');
      expect(result, isNotNull);
      final jpeg = base64Decode(result!);
      final decoded = img.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      expect(decoded!.width, 320);
      expect(decoded.height, 240); // 320 * 600/800
    });

    test('resizes a portrait image by the height edge (longest dim)', () async {
      // A 600x800 portrait: the longest edge is the height (800), so the
      // thumbnail should be 240x320 (320 * 600/800 = 240).
      final bytes = _png(600, 800, 0xFF00FF00);
      final result = await createThumbnail(bytes, 'tall.png');
      expect(result, isNotNull);
      final jpeg = base64Decode(result!);
      final decoded = img.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      expect(decoded!.width, 240); // 320 * 600/800
      expect(decoded.height, 320);
    });

    test('returns null for a non-image pick', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final result = await createThumbnail(bytes, 'doc.pdf');
      expect(result, isNull);
    });

    test('returns null for a corrupt .png', () async {
      // Random bytes with a .png extension: decodeNamedImage returns null,
      // so the helper resolves null (never fatal).
      final bytes = Uint8List.fromList(List.filled(64, 0x42));
      final result = await createThumbnail(bytes, 'broken.png');
      expect(result, isNull);
    });
  });

  // This isolate deliberately leaves MediaKit uninitialized. Player creation
  // must fail nonfatally before consuming media; the initialized, real capture
  // path is covered separately in media_kit_tracer_test.dart.
  group(
      'createThumbnail (video branch) -- media_kit unavailable in flutter test',
      () {
    test(
        'returns null for a video pick when media_kit native backend is unavailable',
        () async {
      // The .mp4 name reaches the video branch; uninitialized MediaKit makes
      // Player construction throw before these bytes are consumed.
      final bytes = Uint8List.fromList(List.filled(128, 0x42));
      final result = await createThumbnail(bytes, 'clip.mp4');
      expect(result, isNull);
    });
  });
}
