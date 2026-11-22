import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img show decodeImage, decodeNamedImage;
import 'package:mime/mime.dart' show lookupMimeType;

import 'image_previews.dart';
import 'video_frame.dart';

/// Decode once and generate both the inline miniature and the clear preview.
/// [videoFrame] is how a video's frame is taken; the platform's by default.
Future<AttachmentPreviews?> createAttachmentPreviews(
    Uint8List bytes, String fileName,
    {TakeVideoFrame videoFrame = takeVideoFrame}) async {
  final mime = lookupMimeType(fileName) ?? '';
  if (mime.startsWith('image/')) {
    return _createImageThumbnail(bytes, fileName);
  }
  if (mime.startsWith('video/')) {
    final frame = await videoFrame(bytes);
    if (frame == null || frame.isEmpty) return null;
    // Decoded, resized and encoded off the main isolate, as an image is.
    return compute(_decodeVideoFrame, frame,
        debugLabel: 'video-attachment-previews');
  }
  return null; // non-image/non-video => no thumbnail
}

/// Image branch. Returns null for
/// non-images / decode failures (never fatal).
Future<AttachmentPreviews?> _createImageThumbnail(
        Uint8List bytes, String fileName) =>
    compute(_decodeImagePreviews, (bytes, fileName),
        debugLabel: 'attachment-previews');

AttachmentPreviews? _decodeVideoFrame(Uint8List frame) {
  try {
    final decoded = img.decodeImage(frame);
    if (decoded == null) return null;
    return encodeImagePreviews(decoded);
  } catch (_) {
    // Never fatal -- resolve null on any decode/encode failure. `catch (_)` on
    // purpose: a corrupt frame can throw a RangeError (an Error, not an
    // Exception), matching the same guard used in _decodeImagePreviews.
    return null;
  }
}

AttachmentPreviews? _decodeImagePreviews((Uint8List, String) input) {
  final (bytes, fileName) = input;
  try {
    final decoded = img.decodeNamedImage(fileName, bytes, frame: 0) ??
        img.decodeImage(bytes, frame: 0);
    if (decoded == null) return null;
    return encodeImagePreviews(decoded, original: bytes);
  } catch (_) {
    // Never fatal -- resolve null on any decode failure. `catch (_)` on
    // purpose: a corrupt or oversized bitmap throws a RangeError, an Error,
    // not an Exception, and that used to escape as an uncaught async error.
    return null;
  }
}
