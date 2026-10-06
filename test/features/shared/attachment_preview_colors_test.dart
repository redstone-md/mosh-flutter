import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/shared/thumbnail.dart';
import 'package:mosh/src/features/shared/image_previews.dart';

Future<Uint8List> _pixels(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      return (await frame.image.toByteData())!.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a wide gamut PNG retains its native displayed colors in the clear JPEG',
      () async {
    final profile =
        await File('test/fixtures/preview-p3-gamma22.icc').readAsBytes();
    final image = img.Image(width: 16, height: 12)
      ..iccProfile =
          img.IccProfile('P3-gamma22', img.IccProfileCompression.none, profile);
    img.fill(image, color: img.ColorRgb8(180, 60, 50));
    final original = img.encodePng(image);
    final previews =
        (await createAttachmentPreviews(original, 'wide-gamut.png'))!;
    final jpeg = base64Decode(previews.previewBase64);
    // The native headless engine may ignore profiles. Verify the standard
    // APP2 payload as well as successful native decoding.
    expect(img.decodeJpg(jpeg)!.iccProfile!.data.sublist(2), profile);
    final expected = await _pixels(original);
    final actual = await _pixels(jpeg);
    for (var channel = 0; channel < 3; channel++) {
      expect(actual[channel], closeTo(expected[channel], 6));
    }
    expect(jpeg.length, lessThanOrEqualTo(128 * 1024));
    expect(previews.miniatureBase64.length, lessThanOrEqualTo(2048));
  });

  test('EXIF rotation is baked before choosing the maximum preview edge',
      () async {
    final image = img.Image(width: 600, height: 400)
      ..exif.imageIfd['Orientation'] = 6;
    final previews = encodeImagePreviews(image);
    final jpeg = img.decodeJpg(base64Decode(previews.previewBase64))!;
    expect(jpeg.width, lessThanOrEqualTo(320));
    expect(jpeg.height, 320);
    expect(jpeg.exif.isEmpty, isTrue);
  });
}
