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
class AttachmentMiniatureImage extends MemoryImage {
  const AttachmentMiniatureImage(super.bytes);

  @override
  ImageStreamCompleter loadImage(
          MemoryImage key, ImageDecoderCallback decode) =>
      super.loadImage(
          key,
          (buffer, {getTargetSize}) =>
              _decodePreview(buffer, decode, getTargetSize, maxEdge: 1024));
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
