// Unit tests for `createAttachmentPreviews` (lib/src/features/shared/
// thumbnail.dart) on the branches its callers do not already pin: a
// portrait image scales by its height, and a video whose frame cannot be
// taken has no previews instead of failing the pick.

import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/shared/thumbnail.dart';

void main() {
  test('a portrait image scales its clear preview by the height edge',
      () async {
    final bytes =
        Uint8List.fromList(img.encodePng(img.Image(width: 600, height: 800)));
    final previews = await createAttachmentPreviews(bytes, 'tall.png');
    final decoded = img.decodeJpg(base64Decode(previews!.previewBase64))!;
    expect((decoded.width, decoded.height), (240, 320));
  });

  // This isolate deliberately leaves MediaKit uninitialized. Player creation
  // must fail nonfatally before consuming media; the initialized, real capture
  // path is covered separately in media_kit_tracer_test.dart.
  test('a video pick has no previews when media_kit is unavailable', () async {
    // The .mp4 name reaches the video branch; uninitialized MediaKit makes
    // Player construction throw before these bytes are consumed.
    final bytes = Uint8List.fromList(List.filled(128, 0x42));
    expect(await createAttachmentPreviews(bytes, 'clip.mp4'), isNull);
  });
}
