/// CallFrameTransport -- the base64<->raw-bytes seam between the Rust
/// FFI [Gateway] and [CallFrameSource] (1:1 with React's base64 wire
/// boundary). The Dart mosh_core frb surface is raw Uint8List; the
/// already-landed call_drain.dart is base64 (mirroring React). This
/// adapter isolates the conversion so call_drain.dart stays untouched.
library;

import 'dart:typed_data';

import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'call_drain.dart' show CallFrameSource;
import 'frame_codec.dart' show bytesToBase64;

class CallFrameTransport implements CallFrameSource {
  CallFrameTransport(this._gateway);
  final Gateway _gateway;

  /// Satisfies [CallFrameSource]: drains raw frame bytes from the
  /// gateway and base64-encodes each for call_drain's openFrame path.
  @override
  Future<List<String>> callDrainFrames(String sessionId, String callId) async {
    final raw = await _gateway.callDrainFrames(sessionId: sessionId, callId: callId);
    return [for (final frame in raw) bytesToBase64(frame)];
  }

  /// Sends a sealed wire frame (raw bytes) to the gateway. Mirrors
  /// React's `gateway.callSendFrame(sessionId, callId, base64)` but
  /// passes raw bytes since the Dart frb surface is raw.
  Future<void> sendFrameBytes(String sessionId, String callId, Uint8List wire) {
    return _gateway.callSendFrame(sessionId: sessionId, callId: callId, frame: wire);
  }
}
