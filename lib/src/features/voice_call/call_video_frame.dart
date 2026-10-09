import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// A renderer-owned RGBA copy. Contains presentation identity, never media keys.
class CallVideoFrame {
  const CallVideoFrame(
      {required this.sessionId,
      required this.callId,
      required this.sequence,
      required this.width,
      required this.height,
      required this.local,
      required this.pixels,
      this.sourceAgeMs = 0});

  static const maximumBytes = 1920 * 1080 * 4;
  static const maximumMetadataBytes = 1024;
  static const magic = [77, 67, 70, 49]; // MCF1
  final String sessionId;
  final String callId;
  final int sequence;
  final int width;
  final int height;
  final bool local;
  final Uint8List pixels;
  final int sourceAgeMs;

  void validate() {
    if (sessionId.isEmpty ||
        sessionId.length > 128 ||
        callId.isEmpty ||
        callId.length > 128 ||
        sequence <= 0 ||
        sourceAgeMs < 0 ||
        width <= 0 ||
        height <= 0 ||
        width > 1920 ||
        height > 1920 ||
        width * height * 4 > maximumBytes ||
        pixels.length != width * height * 4) {
      throw const FormatException('Invalid call frame');
    }
  }

  Uint8List encode() {
    validate();
    final metadata = utf8.encode(jsonEncode({
      'sessionId': sessionId,
      'callId': callId,
      'sequence': sequence,
      'width': width,
      'height': height,
      'local': local,
      'sourceAgeMs': sourceAgeMs,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
    }));
    if (metadata.length > maximumMetadataBytes) {
      throw const FormatException('Frame metadata too large');
    }
    final bytes = Uint8List(12 + metadata.length + pixels.length);
    bytes.setRange(0, 4, magic);
    final header = ByteData.sublistView(bytes);
    header.setUint32(4, metadata.length);
    header.setUint32(8, pixels.length);
    bytes.setRange(12, 12 + metadata.length, metadata);
    bytes.setRange(12 + metadata.length, bytes.length, pixels);
    return bytes;
  }

  static CallVideoFrame decode(Uint8List body, int metadataLength) {
    final m =
        jsonDecode(utf8.decode(Uint8List.sublistView(body, 0, metadataLength)))
            as Map<String, Object?>;
    final frame = CallVideoFrame(
        sessionId: m['sessionId'] as String,
        callId: m['callId'] as String,
        sequence: m['sequence'] as int,
        width: m['width'] as int,
        height: m['height'] as int,
        local: m['local'] as bool,
        sourceAgeMs: (m['sourceAgeMs'] as int) +
            math.max(0,
                DateTime.now().millisecondsSinceEpoch - (m['sentAtMs'] as int)),
        pixels: Uint8List.sublistView(body, metadataLength));
    frame.validate();
    return frame;
  }
}
