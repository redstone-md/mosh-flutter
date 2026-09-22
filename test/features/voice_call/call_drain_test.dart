// Parity tests for `call_drain` (lib/src/features/voice_call/call_drain.dart)
// -- the gateway poll-loop glue that pulls sealed call frames from a
// [CallFrameSource]. This is a fresh Dart suite proving the
// glue behavior end-to-end against the real `frame_crypto` seal/open path
// (no crypto mocking) so the jitter-reorder + skip-on-auth-failure contract
// is exercised faithfully.
// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_drain.dart';
import 'package:mosh/src/features/voice_call/frame_codec.dart';
import 'package:mosh/src/features/voice_call/frame_crypto.dart';
import 'package:mosh/src/features/voice_call/jitter_buffer.dart';

const String KEY_B64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; // 32 zero bytes
const String PREFIX_B64 = 'AAAAAA=='; // 4 zero bytes

class _FakeSource implements CallFrameSource {
  _FakeSource(this.frames);
  List<String> frames;
  @override
  Future<List<String>> callDrainFrames(String sessionId, String callId) async =>
      frames;
}

class _FakeSink implements CallFrameSink {
  final List<({BigInt seq, Uint8List payload})> received = [];
  @override
  void pushFrame(BigInt seq, Uint8List payload) {
    received.add((seq: seq, payload: payload));
  }
}

void main() {
  group('call_drain', () {
    test('drains nothing when source returns no frames', () async {
      final key = await importCallKey(KEY_B64);
      final source = _FakeSource(<String>[]);
      final jitter = JitterBuffer();
      final playback = _FakeSink();

      await drainCallFrames(
        source: source,
        sessionId: 's',
        callId: 'c',
        key: key,
        noncePrefix: PREFIX_B64,
        jitter: jitter,
        playback: playback,
      );

      expect(playback.received, isEmpty);
      expect(jitter.drainReady(), isEmpty);
    });

    test('decrypts, reorders, and plays frames in seq order', () async {
      final key = await importCallKey(KEY_B64);
      // Seal frames with distinct payloads keyed by seq, then deliver them
      // out of order ([3,1,2]). The jitter buffer must reorder to [1,2,3].
      final f1 = await sealFrame(key, PREFIX_B64, BigInt.one,
          CALLER_DIRECTION_BIT, Uint8List.fromList([10]));
      final f2 = await sealFrame(key, PREFIX_B64, BigInt.two,
          CALLER_DIRECTION_BIT, Uint8List.fromList([20]));
      final f3 = await sealFrame(key, PREFIX_B64, BigInt.from(3),
          CALLER_DIRECTION_BIT, Uint8List.fromList([30]));
      final source = _FakeSource(
          [bytesToBase64(f3), bytesToBase64(f1), bytesToBase64(f2)]);
      final jitter = JitterBuffer();
      final playback = _FakeSink();

      await drainCallFrames(
        source: source,
        sessionId: 's',
        callId: 'c',
        key: key,
        noncePrefix: PREFIX_B64,
        jitter: jitter,
        playback: playback,
      );

      expect(playback.received.length, 3);
      expect(playback.received[0].seq, BigInt.one);
      expect(playback.received[0].payload, Uint8List.fromList([10]));
      expect(playback.received[1].seq, BigInt.two);
      expect(playback.received[1].payload, Uint8List.fromList([20]));
      expect(playback.received[2].seq, BigInt.from(3));
      expect(playback.received[2].payload, Uint8List.fromList([30]));
    });

    test('skips frames that fail auth (tampered) and plays the rest', () async {
      final key = await importCallKey(KEY_B64);
      final good = await sealFrame(key, PREFIX_B64, BigInt.one,
          CALLER_DIRECTION_BIT, Uint8List.fromList([10]));
      final tampered = await sealFrame(key, PREFIX_B64, BigInt.two,
          CALLER_DIRECTION_BIT, Uint8List.fromList([20]));
      tampered[tampered.length - 1] ^= 0xff; // flip last byte -> GCM auth fails
      final source =
          _FakeSource([bytesToBase64(good), bytesToBase64(tampered)]);
      final jitter = JitterBuffer();
      final playback = _FakeSink();

      await drainCallFrames(
        source: source,
        sessionId: 's',
        callId: 'c',
        key: key,
        noncePrefix: PREFIX_B64,
        jitter: jitter,
        playback: playback,
      );

      expect(playback.received.length, 1);
      expect(playback.received[0].seq, BigInt.one);
      expect(playback.received[0].payload, Uint8List.fromList([10]));
    });
  });
}
