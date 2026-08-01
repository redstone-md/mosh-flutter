/// Thumbnail generator -- the 1-в-1 port of React's `createThumbnail`
/// (src/features/private-dm/attachment-utils.ts L133-141) for the IMAGE branch
/// only. React's `imageThumbnail` uses `createImageBitmap` + a canvas; this
/// port uses the pure-Dart `image` package (decode + copyResize + encodeJpg),
/// so it works on desktop + mobile + web with no native plugin.
//
// React `videoThumbnail` (a `<video>` seek + canvas draw) is NOT ported here:
// Flutter has no cheap offscreen video frame capture without a
// `video_player` + `RepaintBoundary` round-trip, which is a larger slice.
// For non-image picks this returns null (mirrors React's non-image branch).
// A null thumbnail is never fatal -- React resolves undefined on any decode
// failure; the gateway treats a null `thumbnailBase64` as "no preview".
//
// Output: a base64-encoded JPEG (no `data:` prefix), matching React's
// `canvasToBase64` (`toDataURL("image/jpeg", 0.7)` then strip the prefix).
// The 320px max-edge + 70% quality mirror React's `THUMBNAIL_MAX_EDGE = 320`
// + the `0.7` quality arg. Aspect is preserved via `copyResize` (width-only
// resize auto-computes height, matching React's `scaledSize`).
library;

import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:image/image.dart' as img
    show decodeNamedImage, copyResize, encodeJpg;
import 'package:mime/mime.dart' show lookupMimeType;

/// The max edge (px) for a thumbnail -- 1-в-1 with React `THUMBNAIL_MAX_EDGE`.
const int _thumbnailMaxEdge = 320;

/// JPEG quality (0-100) -- React's `0.7` (a 0-1 value) maps to 70 here.
const int _jpegQuality = 70;

/// Generates a base64-encoded JPEG thumbnail for an image file, or null for
/// non-images / decode failures (mirrors React `createThumbnail` returning
/// `undefined` for non-image types and on any `createImageBitmap` error).
///
/// [fileName] is used to infer the decoder (via `decodeNamedImage`, which
/// keys off the extension) -- faster than `decodeImage`'s format-guessing.
/// [bytes] is the raw file content (already read by AttachmentPicker).
///
/// Image-only: video thumbnails are a later slice (see module doc).
Future<String?> createThumbnail(Uint8List bytes, String fileName) async {
  final mime = lookupMimeType(fileName) ?? '';
  if (!mime.startsWith('image/')) return null; // React: non-image => undefined
  try {
    final decoded = img.decodeNamedImage(fileName, bytes);
    if (decoded == null) return null;
    // React scaledSize: scale = min(1, MAX / max(w, h, 1)); the longest edge
    // becomes MAX, the other scales by the same factor. copyResize with only
    // width set auto-computes height to preserve aspect -- so resize by the
    // LONGER dimension: width=MAX for landscape/square, height=MAX for
    // portrait (so the 320 edge is the portrait height).
    final w = decoded.width;
    final h = decoded.height;
    final resized = w >= h
        ? img.copyResize(decoded, width: _thumbnailMaxEdge)
        : img.copyResize(decoded, height: _thumbnailMaxEdge);
    final jpeg = img.encodeJpg(resized, quality: _jpegQuality);
    return base64Encode(jpeg);
  } on Exception {
    return null; // never fatal -- mirrors React's try/catch -> undefined
  }
}
