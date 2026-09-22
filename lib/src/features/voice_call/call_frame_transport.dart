// CallFrameTransport -- the base64<->raw-bytes seam between the Rust
// FFI [Gateway] and [CallFrameSource]. The Dart mosh_core frb surface is
// raw Uint8List, while call_drain.dart works in base64. This adapter
// isolates the conversion so call_drain.dart stays untouched.
library;

import 'dart:typed_data';

import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'call_drain.dart' show CallFrameSource;
import 'frame_codec.dart' show bytesToBase64;

class CallFrameTransport implements CallFrameSource {
  CallFrameTransport(this._bridge);
  final BridgeFacade _bridge;

  /// Satisfies [CallFrameSource]: drains raw frame bytes from the
  /// bridge facade and base64-encodes each for call_drain's openFrame path.
  @override
  Future<List<String>> callDrainFrames(String sessionId, String callId) async {
    final raw =
        await _bridge.callDrainFrames(sessionId: sessionId, callId: callId);
    return [for (final frame in raw) bytesToBase64(frame)];
  }

  /// Sends a sealed wire frame (raw bytes) to the bridge.
  Future<void> sendFrameBytes(String sessionId, String callId, Uint8List wire) {
    return _bridge.callSendFrame(
        sessionId: sessionId, callId: callId, frame: wire);
  }
}
