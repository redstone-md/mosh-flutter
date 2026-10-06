import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'preview_color_profile.dart';

/// The miniature travels inside the message; the clear JPEG is a separate blob.
class AttachmentPreviews {
  const AttachmentPreviews({
    required this.miniatureBase64,
    required this.previewBase64,
  });

  final String miniatureBase64;
  final String previewBase64;
}

const _miniatureMaxBase64 = 2048;
const _previewMaxBytes = 128 * 1024;

AttachmentPreviews encodeImagePreviews(img.Image decoded,
    {Uint8List? original}) {
  final profile = previewColorProfile(decoded, original);
  final orientation = decoded.exif.imageIfd.orientation;
  final oriented = orientation != null && orientation != 1
      ? img.bakeOrientation(decoded)
      : decoded;
  final preview = _resize(oriented, 320)
    ..exif = img.ExifData()
    ..iccProfile = null;
  final jpeg =
      withPreviewColorProfile(img.encodeJpg(preview, quality: 70), profile);
  if (jpeg.length > _previewMaxBytes) {
    throw const FormatException(
        'Cannot encode an attachment preview within its byte budget');
  }
  return AttachmentPreviews(
    miniatureBase64: _miniature(preview, profile),
    previewBase64: base64Encode(jpeg),
  );
}

String _miniature(img.Image image, Uint8List? profile) {
  for (final colorProfile in [if (profile != null) profile, null]) {
    for (final edge in [48, 36, 24, 12]) {
      final jpeg = withPreviewColorProfile(
          img.encodeJpg(_resize(image, edge), quality: 50), colorProfile);
      final encoded = base64Encode(jpeg);
      if (encoded.length <= _miniatureMaxBase64) return encoded;
    }
  }
  throw const FormatException('Cannot encode an attachment miniature');
}

img.Image _resize(img.Image image, int maximum) {
  final edge =
      min(maximum, image.width > image.height ? image.width : image.height);
  return image.width >= image.height
      ? img.copyResize(image,
          width: edge, interpolation: img.Interpolation.average)
      : img.copyResize(image,
          height: edge, interpolation: img.Interpolation.average);
}
