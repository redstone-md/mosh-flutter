import 'dart:collection' show LinkedHashMap;
import 'dart:convert' show base64Decode;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Decoded inline miniature: its bytes and the size read from its header.
typedef DecodedMiniature = ({Uint8List bytes, Size? size});

/// Total retained bytes (base64 source plus decoded buffer) across entries.
const int _miniatureCacheMaxBytes = 4 * 1024 * 1024;

/// Larger entries are decoded on demand but never retained. Current
/// miniatures are at most 2 KiB of base64 and legacy ones 32 KiB.
const int _miniatureEntryMaxBytes = 128 * 1024;

final LinkedHashMap<String, DecodedMiniature> _miniatureCache =
    LinkedHashMap<String, DecodedMiniature>();
int _miniatureCacheBytes = 0;
final DecodedMiniature _emptyMiniature = (bytes: Uint8List(0), size: null);

// Two bytes per UTF-16 code unit also cover malformed non-ASCII keys.
int _entryBytes(String source, DecodedMiniature decoded) =>
    source.length * 2 + decoded.bytes.lengthInBytes;

/// Decodes a base64 miniature once and reuses the result on later builds.
///
/// Message lists rebuild every attachment card on each transfer progress or
/// state change; decoding the base64 and parsing its header in every build
/// blocks the UI thread. A malformed value yields empty bytes so the image's
/// errorBuilder renders the broken-image fallback, as before.
DecodedMiniature decodeMiniature(String? source) {
  if (source == null || source.isEmpty) return _emptyMiniature;
  final cached = _miniatureCache.remove(source);
  if (cached != null) {
    _miniatureCache[source] = cached; // mark as most recently used
    return cached;
  }
  DecodedMiniature decoded;
  try {
    final bytes = base64Decode(source);
    decoded = (bytes: bytes, size: encodedImageSize(bytes));
  } catch (_) {
    decoded = _emptyMiniature;
  }
  final entryBytes = _entryBytes(source, decoded);
  if (entryBytes > _miniatureEntryMaxBytes) return decoded;
  _miniatureCache[source] = decoded;
  _miniatureCacheBytes += entryBytes;
  while (_miniatureCacheBytes > _miniatureCacheMaxBytes) {
    final oldest = _miniatureCache.keys.first;
    final evicted = _miniatureCache.remove(oldest)!;
    _miniatureCacheBytes -= _entryBytes(oldest, evicted);
  }
  return decoded;
}

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
  var orientation = 1;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    final marker = bytes[offset + 1];
    if (marker == 0xFF) {
      offset++;
      continue;
    }
    final length = data.getUint16(offset + 2);
    if (marker == 0xE1 && orientation == 1) {
      orientation = _exifOrientation(data, offset + 4, offset + 2 + length);
    }
    if (_isStartOfFrame(marker)) {
      if (offset + 9 > bytes.length) return null;
      final (width, height) =
          (data.getUint16(offset + 7), data.getUint16(offset + 5));
      // Orientations 5-8 rotate by 90 degrees when Flutter displays them.
      return orientation >= 5 && orientation <= 8
          ? _positive(height, width)
          : _positive(width, height);
    }
    if (length < 2) return null;
    offset += 2 + length;
  }
  return null;
}

/// Legacy miniatures kept the source EXIF orientation with unrotated pixels.
/// Reads tag 0x0112 from IFD0 of an `Exif\0\0` APP1 payload, else 1.
int _exifOrientation(ByteData data, int start, int end) {
  try {
    if (end > data.lengthInBytes ||
        data.getUint32(start) != 0x45786966 ||
        data.getUint16(start + 4) != 0) {
      return 1;
    }
    final tiff = start + 6;
    final endian = data.getUint16(tiff) == 0x4949 ? Endian.little : Endian.big;
    final ifd = tiff + data.getUint32(tiff + 4, endian);
    final count = data.getUint16(ifd, endian);
    for (var entry = ifd + 2; entry < ifd + 2 + count * 12; entry += 12) {
      if (entry + 12 > end) return 1;
      if (data.getUint16(entry, endian) == 0x0112) {
        return data.getUint16(entry + 8, endian);
      }
    }
  } on RangeError {
    // A truncated EXIF payload leaves the stored axes.
  }
  return 1;
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
