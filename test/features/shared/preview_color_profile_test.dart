import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosh/src/features/shared/image_previews.dart';
import 'package:mosh/src/features/shared/preview_color_profile.dart';
import 'package:mosh/src/features/shared/thumbnail.dart';

Uint8List _profile(int length) {
  final fixture =
      File('test/fixtures/preview-p3-gamma22.icc').readAsBytesSync();
  final bytes = Uint8List(length)..setRange(0, fixture.length, fixture);
  ByteData.sublistView(bytes).setUint32(0, length);
  return bytes;
}

Uint8List _jpegWithChunks(Uint8List profile, List<int> order) {
  final jpeg = img.encodeJpg(img.Image(width: 16, height: 12));
  final bytes = BytesBuilder()..add(jpeg.sublist(0, 2));
  for (final index in order) {
    final chunk = index == 1
        ? profile.sublist(0, profile.length ~/ 2)
        : profile.sublist(profile.length ~/ 2);
    final length = chunk.length + 16;
    bytes
      ..add([255, 226, length >> 8, length & 255])
      ..add(ascii.encode('ICC_PROFILE\u0000'))
      ..add([index, 2])
      ..add(chunk);
  }
  return (bytes..add(jpeg.sublist(2))).takeBytes();
}

void main() {
  test(
      'standard JPEG ICC chunks retain their complete profile in sequence order',
      () async {
    final profile = _profile(568);
    final original = _jpegWithChunks(profile, [2, 1]);
    final previews = (await createAttachmentPreviews(original, 'profile.jpg'))!;
    for (final value in [previews.previewBase64, previews.miniatureBase64]) {
      final jpeg = base64Decode(value);
      expect(previewColorProfile(img.decodeJpg(jpeg)!, jpeg), profile);
    }
  });

  test('missing and duplicated JPEG profile chunks are ignored', () async {
    for (final order in [
      [1],
      [1, 1, 2]
    ]) {
      final original = _jpegWithChunks(_profile(568), order);
      final previews =
          (await createAttachmentPreviews(original, 'invalid.jpg'))!;
      expect(img.decodeJpg(base64Decode(previews.previewBase64))!.iccProfile,
          isNull);
    }
  });

  test(
      'a bounded large profile stays in the clear JPEG while the miniature fits',
      () {
    final profile = _profile(64 * 1024);
    final image = img.Image(width: 24, height: 16)
      ..iccProfile =
          img.IccProfile('large', img.IccProfileCompression.none, profile);
    final previews = encodeImagePreviews(image);
    final clear = base64Decode(previews.previewBase64);
    expect(clear.length, lessThanOrEqualTo(128 * 1024));
    expect(previewColorProfile(img.decodeJpg(clear)!, clear), profile);
    expect(previews.miniatureBase64.length, lessThanOrEqualTo(2048));
    expect(img.decodeJpg(base64Decode(previews.miniatureBase64))!.iccProfile,
        isNull);
    expect(image.iccProfile!.data, profile);
  });

  test('compressed profiles cannot inflate beyond the preview metadata budget',
      () async {
    final image = img.Image(width: 16, height: 12)
      ..iccProfile = img.IccProfile(
          'oversized', img.IccProfileCompression.none, _profile(64 * 1024 + 1));
    final original = img.encodePng(image);
    expect(original.length, lessThan(2048));
    expect(await createAttachmentPreviews(original, 'oversized.png'), isNull);
  });

  test(
      'oversized standard JPEG profiles are refused before producing a preview',
      () async {
    final original = _jpegWithChunks(_profile(64 * 1024 + 1), [1, 2]);
    expect(await createAttachmentPreviews(original, 'oversized.jpg'), isNull);
  });

  test('invalid profile headers and tag ranges do not reach the JPEG encoder',
      () {
    final variants = [
      Uint8List(16),
      _profile(568)..[36] = 0,
      _profile(568)..[3] = 1,
      _profile(568),
      _profile(568),
    ];
    ByteData.sublistView(variants[3]).setUint32(128, 5000);
    ByteData.sublistView(variants[4]).setUint32(136, 600);
    for (final profile in variants) {
      final image = img.Image(width: 16, height: 12)
        ..iccProfile =
            img.IccProfile('invalid', img.IccProfileCompression.none, profile);
      final previews = encodeImagePreviews(image);
      expect(img.decodeJpg(base64Decode(previews.previewBase64))!.iccProfile,
          isNull);
    }
  });

  test(
      'unsupported color spaces are refused instead of silently relabelled RGB',
      () {
    final profile = _profile(568);
    ByteData.sublistView(profile).setUint32(16, 0x434d594b);
    final image = img.Image(width: 16, height: 12)
      ..iccProfile =
          img.IccProfile('CMYK', img.IccProfileCompression.none, profile);
    expect(() => encodeImagePreviews(image), throwsFormatException);
  });
}
