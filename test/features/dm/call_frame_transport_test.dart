// Tests for `CallFrameTransport` -- the base64<->raw-bytes adapter between
// the raw-Uint8List Rust FFI `Gateway` and the base64-string `CallFrameSource`
// consumed by call_drain. Mirrors the parity intent of React's call-drain seam
// but proves the encoding boundary in isolation, no device needed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/call_drain.dart' show CallFrameSource;
import 'package:mosh/src/features/dm/call_frame_transport.dart';
import 'package:mosh/src/gateway/gateway.dart' show Gateway;

/// Minimal recording Gateway: only `callSendFrame` + `callDrainFrames` are
/// exercised here; the rest throw UnimplementedError so any other call surface
/// surfaces loudly in the test instead of silently no-opping.
class _RecordingGateway implements Gateway {
  final List<({String sessionId, String callId, Uint8List frame})> sent = [];
  String? lastDrainSessionId;
  String? lastDrainCallId;
  List<Uint8List> drainReturn = const [];

  @override
  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  }) async {
    sent.add((sessionId: sessionId, callId: callId, frame: frame));
  }

  @override
  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  }) async {
    lastDrainSessionId = sessionId;
    lastDrainCallId = callId;
    return drainReturn;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

/// Proves `CallFrameTransport` is usable wherever a `CallFrameSource` is
/// expected (i.e. the `implements` relationship holds at the type level and
/// behaves correctly when invoked through the interface).
Future<int> _countFrames(CallFrameSource source) async =>
    (await source.callDrainFrames('x', 'y')).length;

void main() {
  group('call_frame_transport', () {
    test('callDrainFrames base64-encodes each raw frame from the gateway', () async {
      final gateway = _RecordingGateway()
        ..drainReturn = [Uint8List.fromList([1, 2, 3]), Uint8List.fromList([4, 5])];
      final transport = CallFrameTransport(gateway);

      final result = await transport.callDrainFrames('s', 'c');

      expect(result, ['AQID', 'BAU=']);
    });

    test('callDrainFrames passes sessionId and callId through to the gateway', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);

      await transport.callDrainFrames('s1', 'c1');

      expect(gateway.lastDrainSessionId, 's1');
      expect(gateway.lastDrainCallId, 'c1');
    });

    test('callDrainFrames returns an empty list when the gateway returns none', () async {
      final gateway = _RecordingGateway()..drainReturn = const [];
      final transport = CallFrameTransport(gateway);

      final result = await transport.callDrainFrames('s', 'c');

      expect(result, isEmpty);
    });

    test('sendFrameBytes forwards the raw bytes to the gateway', () async {
      final gateway = _RecordingGateway();
      final transport = CallFrameTransport(gateway);

      await transport.sendFrameBytes('s', 'c', Uint8List.fromList([9, 9, 9]));

      expect(gateway.sent.length, 1);
      expect(gateway.sent.single.sessionId, 's');
      expect(gateway.sent.single.callId, 'c');
      expect(gateway.sent.single.frame, Uint8List.fromList([9, 9, 9]));
    });

    test('satisfies CallFrameSource (can be passed where a source is expected)', () async {
      final gateway = _RecordingGateway()
        ..drainReturn = [Uint8List.fromList([1, 2, 3]), Uint8List.fromList([4, 5])];

      // Upcast to the interface to prove the implements relationship holds.
      final CallFrameSource source = CallFrameTransport(gateway);

      final count = await _countFrames(source);

      expect(count, 2);
    });
  });
}
