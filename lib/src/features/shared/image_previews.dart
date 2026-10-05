import 'dart:convert';
import 'dart:math' show min;

import 'package:image/image.dart' as img;

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

AttachmentPreviews encodeImagePreviews(img.Image decoded) {
  final preview = _resize(decoded, 320);
  return AttachmentPreviews(
    miniatureBase64: _miniature(preview),
    previewBase64: base64Encode(img.encodeJpg(preview, quality: 70)),
  );
}

String _miniature(img.Image image) {
  for (final edge in [48, 36, 24, 12]) {
    final jpeg = img.encodeJpg(_resize(image, edge), quality: 50);
    final encoded = base64Encode(jpeg);
    if (encoded.length <= _miniatureMaxBase64) return encoded;
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
