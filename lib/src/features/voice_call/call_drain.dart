import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;

import 'frame_crypto.dart';
import 'jitter_buffer.dart';

/// Where decoded, reordered frames go. The playback handle, narrowed.
abstract interface class CallFrameSink {
  void pushFrame(BigInt seq, Uint8List payload);
}

/// Drains pending wire frames, decrypts each (skipping any that fail
/// auth), reorders them through the jitter buffer, and feeds the ready
/// ones to playback. Uses named params (Dart idiom for a 7-arg surface;
/// matches the call-site convention elsewhere in this feature).
Future<void> drainCallFrames({
  required BridgeFacade bridge,
  required String sessionId,
  required String callId,
  required SecretKey key,
  required String noncePrefix,
  required JitterBuffer jitter,
  required CallFrameSink playback,
}) async {
  final frames =
      await bridge.callDrainFrames(sessionId: sessionId, callId: callId);
  if (frames.isEmpty) return;
  for (final frame in frames) {
    final opened = await openFrame(key, noncePrefix, frame);
    if (opened != null) {
      jitter.push(BufferedFrame(seq: opened.seq, payload: opened.payload));
    }
  }
  for (final buffered in jitter.drainReady()) {
    playback.pushFrame(buffered.seq, buffered.payload);
  }
}
