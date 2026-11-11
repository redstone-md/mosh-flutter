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

  /// How long a frame stays on screen when no newer one follows, and the age
  /// past which a frame is never drawn. A shorter stall freezes the picture.
  static const lifetimeMs = 5000;
  static const maximumBytes = 1920 * 1080 * 4;
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
}
