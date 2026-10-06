import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Reject excessive intrinsic dimensions before the codec allocates pixels.
class AttachmentPreviewFileImage extends FileImage {
  const AttachmentPreviewFileImage(super.file);

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) =>
      super.loadImage(
          key,
          (buffer, {getTargetSize}) =>
              _decodePreview(buffer, decode, getTargetSize, maxEdge: 320));
}

/// Leave room for legacy portrait thumbnails generated before the EXIF fix.
///
/// Keyed by the encoded [source] rather than byte identity, so a rebuilt or
/// reopened chat reuses the decoded miniature from the image cache.
class AttachmentMiniatureImage extends MemoryImage {
  const AttachmentMiniatureImage(super.bytes, {required this.source});

  final String source;

  @override
  ImageStreamCompleter loadImage(
          MemoryImage key, ImageDecoderCallback decode) =>
      super.loadImage(
          key,
          (buffer, {getTargetSize}) =>
              _decodePreview(buffer, decode, getTargetSize, maxEdge: 1024));

  @override
  bool operator ==(Object other) =>
      other is AttachmentMiniatureImage &&
      other.source == source &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(source, scale);
}

Future<ui.Codec> _decodePreview(ui.ImmutableBuffer buffer,
    ImageDecoderCallback decode, ui.TargetImageSizeCallback? targetSize,
    {required int maxEdge}) async {
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width > maxEdge || descriptor.height > maxEdge) {
        throw const FormatException(
            'Attachment preview dimensions are too large');
      }
    } finally {
      descriptor.dispose();
    }
  } catch (_) {
    buffer.dispose();
    rethrow;
  }
  return decode(buffer, getTargetSize: targetSize);
}

/// Reads JPEG or PNG dimensions from the header without decoding pixels.
///
/// Miniatures share the aspect ratio of the clear preview and the original,
/// so the card can reserve its final height before any image decodes.
Size? encodedImageSize(Uint8List bytes) => _pngSize(bytes) ?? _jpegSize(bytes);

Size? _pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  return _positive(data.getUint32(16), data.getUint32(20));
}

Size? _jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  final data = ByteData.sublistView(bytes);
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    final marker = bytes[offset + 1];
    if (marker == 0xFF) {
      offset++;
      continue;
    }
    final length = data.getUint16(offset + 2);
    if (_isStartOfFrame(marker)) {
      if (offset + 9 > bytes.length) return null;
      return _positive(data.getUint16(offset + 7), data.getUint16(offset + 5));
    }
    if (length < 2) return null;
    offset += 2 + length;
  }
  return null;
}

/// SOF0-SOF15, excluding DHT (C4), JPG (C8) and DAC (CC).
bool _isStartOfFrame(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;

Size? _positive(int width, int height) =>
    width > 0 && height > 0 ? Size(width.toDouble(), height.toDouble()) : null;
