import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const _profileMaxBytes = 64 * 1024;
final _iccSignature = ascii.encode('ICC_PROFILE\u0000');

/// image 4.8 drops JPEG ICC chunks and writes their APP2 headers incorrectly.
/// Keep its pixel codec; handle only the bounded color-profile container here.
Uint8List? previewColorProfile(img.Image image, Uint8List? original) {
  final Uint8List? profile;
  if (original != null &&
      original.length >= 2 &&
      original[0] == 255 &&
      original[1] == 216) {
    profile = _jpegProfile(original);
  } else {
    final embedded = image.iccProfile;
    profile = embedded == null ? null : _inflate(embedded);
  }
  if (profile == null || !_validProfile(profile)) return null;
  if (ByteData.sublistView(profile).getUint32(16) != 0x52474220) {
    throw const FormatException('Unsupported preview color space');
  }
  return profile;
}

Uint8List _inflate(img.IccProfile profile) {
  final sink = _ProfileSink();
  if (profile.compression == img.IccProfileCompression.none) {
    sink.add(profile.data);
  } else {
    ZLibDecoder().startChunkedConversion(sink)
      ..add(profile.data)
      ..close();
  }
  return sink.bytes.takeBytes();
}

bool _validProfile(Uint8List bytes) {
  if (bytes.length < 132) return false;
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0) != bytes.length ||
      header.getUint32(36) != 0x61637370) {
    return false;
  }
  final tags = header.getUint32(128);
  if (132 + tags * 12 > bytes.length) return false;
  for (var offset = 132; offset < 132 + tags * 12; offset += 12) {
    final start = header.getUint32(offset + 4);
    final length = header.getUint32(offset + 8);
    if (start < 128 || start + length > bytes.length) return false;
  }
  return true;
}

Uint8List? _jpegProfile(Uint8List original) {
  final chunks = <int, Uint8List>{};
  int? count;
  var length = 0;
  for (final segment in _jpegApp2(original)) {
    if (segment.length < 14 || !_hasSignature(segment)) continue;
    final index = segment[12];
    final total = segment[13];
    if (index == 0 ||
        index > total ||
        (count != null && count != total) ||
        chunks.containsKey(index)) {
      return null;
    }
    count = total;
    final data = Uint8List.sublistView(segment, 14);
    length += data.length;
    if (length > _profileMaxBytes) {
      throw const FormatException('Preview color profile is too large');
    }
    chunks[index] = data;
  }
  if (count == null || chunks.length != count) return null;
  final bytes = BytesBuilder(copy: false);
  for (var index = 1; index <= count; index++) {
    bytes.add(chunks[index]!);
  }
  return bytes.takeBytes();
}

Iterable<Uint8List> _jpegApp2(Uint8List bytes) sync* {
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 255) return;
    if (bytes[offset + 1] == 255) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    if (marker == 218 || marker == 217) return;
    final length = ByteData.sublistView(bytes).getUint16(offset + 2);
    final end = offset + 2 + length;
    if (length < 2 || end > bytes.length) return;
    if (marker == 226) yield Uint8List.sublistView(bytes, offset + 4, end);
    offset = end;
  }
}

bool _hasSignature(Uint8List segment) {
  for (var i = 0; i < _iccSignature.length; i++) {
    if (segment[i] != _iccSignature[i]) return false;
  }
  return true;
}

/// Package ICC chunks as specified by ICC's JPEG embedding convention.
Uint8List withPreviewColorProfile(Uint8List jpeg, Uint8List? profile) {
  if (profile == null) return jpeg;
  const chunkSize = 65519;
  final count = (profile.length + chunkSize - 1) ~/ chunkSize;
  final bytes = BytesBuilder(copy: false)..add(jpeg.sublist(0, 2));
  for (var index = 0; index < count; index++) {
    final end = ((index + 1) * chunkSize).clamp(0, profile.length);
    final chunk = Uint8List.sublistView(profile, index * chunkSize, end);
    final header = Uint8List(18);
    ByteData.sublistView(header)
      ..setUint16(0, 0xffe2)
      ..setUint16(2, chunk.length + 16);
    header.setRange(4, 16, _iccSignature);
    header[16] = index + 1;
    header[17] = count;
    bytes
      ..add(header)
      ..add(chunk);
  }
  return (bytes..add(Uint8List.sublistView(jpeg, 2))).takeBytes();
}

class _ProfileSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > _profileMaxBytes) {
      throw const FormatException('Preview color profile is too large');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
