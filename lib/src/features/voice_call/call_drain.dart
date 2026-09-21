/// Gateway poll-loop glue for voice-call frame draining. Pulls pending wire
/// frames for a call from the [CallFrameSource] gateway, decrypts each
/// (skipping any that fail auth), pushes the survivors into the
/// [JitterBuffer], then drains the ready (reordered) frames to the
/// [CallFrameSink] playback handle. Pure of Flutter so the poll loop can
/// guard it and so it is unit-testable.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'frame_codec.dart';
import 'frame_crypto.dart';
import 'jitter_buffer.dart';

/// Pulls pending wire frames for a call. The only gateway method this
/// module needs.
abstract interface class CallFrameSource {
  Future<List<String>> callDrainFrames(String sessionId, String callId);
}

/// Where decoded, reordered frames go. The playback handle, narrowed.
abstract interface class CallFrameSink {
  void pushFrame(BigInt seq, Uint8List payload);
}

/// Drains pending wire frames, decrypts each (skipping any that fail
/// auth), reorders them through the jitter buffer, and feeds the ready
/// ones to playback. Uses named params (Dart idiom for a 7-arg surface;
/// matches the call-site convention elsewhere in this feature).
Future<void> drainCallFrames({
  required CallFrameSource source,
  required String sessionId,
  required String callId,
  required SecretKey key,
  required String noncePrefix,
  required JitterBuffer jitter,
  required CallFrameSink playback,
}) async {
  final frames = await source.callDrainFrames(sessionId, callId);
  if (frames.isEmpty) return;
  for (final frameB64 in frames) {
    final opened = await openFrame(key, noncePrefix, bytesFromBase64(frameB64));
    if (opened != null) {
      jitter.push(BufferedFrame(seq: opened.seq, payload: opened.payload));
    }
  }
  for (final buffered in jitter.drainReady()) {
    playback.pushFrame(buffered.seq, buffered.payload);
  }
}
