import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/image_previews.dart';

Uint8List _detailedPng() {
  final image = img.Image(width: 640, height: 480);
  final random = Random(56);
  for (final pixel in image) {
    pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test(
      'large image metadata does not prevent either preview or change the original',
      () async {
    final image = img.Image(width: 320, height: 240)
      ..exif.imageIfd['ImageDescription'] = 'x' * (192 * 1024);
    final original = Uint8List.fromList(img.encodePng(image));
    final picked = await ingestAttachment(
        bytes: original, fileName: 'metadata.png', maxBytes: 50 * 1024 * 1024);
    expect(base64Decode(picked!.dataBase64), original);
    expect(picked.thumbnailBase64!.length, lessThanOrEqualTo(2048));
    final bytes = base64Decode(picked.previewBase64!);
    expect(bytes.length, lessThanOrEqualTo(128 * 1024));
    final preview = img.decodeJpg(bytes)!;
    expect(preview.width, 320);
    expect(preview.height, 240);
    expect(preview.iccProfile, isNull);
    expect(preview.exif.isEmpty, isTrue);
  });

  test('small images retain their dimensions and both decodable previews', () {
    final image = img.Image(width: 16, height: 10, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(30, 90, 150, 180));
    final previews = encodeImagePreviews(image);
    for (final encoded in [previews.miniatureBase64, previews.previewBase64]) {
      final decoded = img.decodeJpg(base64Decode(encoded))!;
      expect(decoded.width, 16);
      expect(decoded.height, 10);
    }
    expect(previews.miniatureBase64.length, lessThanOrEqualTo(2048));
  });

  test(
      'a detailed miniature shrinks to its byte budget while the clear preview keeps its size',
      () {
    final image = img.Image(width: 48, height: 48);
    final random = Random(56);
    for (final pixel in image) {
      pixel.setRgb(
          random.nextInt(256), random.nextInt(256), random.nextInt(256));
    }
    final previews = encodeImagePreviews(image);
    final miniature = img.decodeJpg(base64Decode(previews.miniatureBase64))!;
    final preview = img.decodeJpg(base64Decode(previews.previewBase64))!;
    expect(previews.miniatureBase64.length, lessThanOrEqualTo(2048));
    expect(miniature.width, lessThan(48));
    expect(preview.width, 48);
  });

  test('a detailed PNG keeps a decodable miniature within the message budget',
      () async {
    final original = _detailedPng();
    final picked = await ingestAttachment(
      bytes: original,
      fileName: 'Bildschirmfoto 2026-10-05 um 21.31.39.png',
      maxBytes: 50 * 1024 * 1024,
    );
    expect(picked, isNotNull);
    expect(base64Decode(picked!.dataBase64), original);
    expect(picked.mime, 'image/png');
    expect(picked.thumbnailBase64, isNotNull);
    expect(picked.thumbnailBase64!.length, lessThanOrEqualTo(2048));
    final miniature = img.decodeJpg(base64Decode(picked.thumbnailBase64!));
    expect(miniature, isNotNull);
    expect(miniature!.width, lessThanOrEqualTo(48));
    expect(miniature.height, lessThanOrEqualTo(48));
    expect(picked.previewBase64, isNotNull);
    final preview = img.decodeJpg(base64Decode(picked.previewBase64!));
    expect(preview, isNotNull);
    expect(preview!.width, 320);
    expect(preview.height, 240);
    expect(preview.width, greaterThan(miniature.width));
  });

  test('an unreadable image is refused instead of sent without a preview', () {
    expect(
      ingestAttachment(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'broken.png',
        maxBytes: 1024,
      ),
      throwsA(isA<AttachmentPreviewException>()),
    );
  });
}
