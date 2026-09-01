// Tests for `CallFrameTransport` -- the base64<->raw-bytes adapter between
// the raw-Uint8List Rust FFI `Gateway` and the base64-string `CallFrameSource`
// consumed by call_drain. Mirrors the parity intent of React's call-drain seam
// but proves the encoding boundary in isolation, no device needed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_drain.dart'
    show CallFrameSource;
import 'package:mosh/src/features/voice_call/call_frame_transport.dart';
import '../../support/scriptable_gateway.dart';

/// Proves `CallFrameTransport` is usable wherever a `CallFrameSource` is
/// expected (i.e. the `implements` relationship holds at the type level and
/// behaves correctly when invoked through the interface).
Future<int> _countFrames(CallFrameSource source) async =>
    (await source.callDrainFrames('x', 'y')).length;

void main() {
  group('call_frame_transport', () {
    test('callDrainFrames base64-encodes each raw frame from the gateway',
        () async {
      final gateway = ScriptableGateway()
        ..seedCallFrames([
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([4, 5])
        ]);
      final transport = CallFrameTransport(gateway);

      final result = await transport.callDrainFrames('s', 'c');

      expect(result, ['AQID', 'BAU=']);
    });

    test('callDrainFrames passes sessionId and callId through to the gateway',
        () async {
      final gateway = ScriptableGateway();
      final transport = CallFrameTransport(gateway);

      await transport.callDrainFrames('s1', 'c1');

      expect(
          gateway
              .lastCall(GatewayMethod.callDrainFrames)
              ?.arg<String>('sessionId'),
          's1');
      expect(
          gateway
              .lastCall(GatewayMethod.callDrainFrames)
              ?.arg<String>('callId'),
          'c1');
    });

    test('callDrainFrames returns an empty list when the gateway returns none',
        () async {
      final gateway = ScriptableGateway()..seedCallFrames(const []);
      final transport = CallFrameTransport(gateway);

      final result = await transport.callDrainFrames('s', 'c');

      expect(result, isEmpty);
    });

    test('sendFrameBytes forwards the raw bytes to the gateway', () async {
      final gateway = ScriptableGateway();
      final transport = CallFrameTransport(gateway);

      await transport.sendFrameBytes('s', 'c', Uint8List.fromList([9, 9, 9]));

      expect(gateway.countOf(GatewayMethod.callSendFrame), 1);
      expect(
          gateway
              .lastCall(GatewayMethod.callSendFrame)
              ?.arg<String>('sessionId'),
          's');
      expect(
          gateway.lastCall(GatewayMethod.callSendFrame)?.arg<String>('callId'),
          'c');
      expect(
          gateway
              .argValues<Uint8List>(GatewayMethod.callSendFrame, 'frame')
              .single,
          Uint8List.fromList([9, 9, 9]));
    });

    test('satisfies CallFrameSource (can be passed where a source is expected)',
        () async {
      final gateway = ScriptableGateway()
        ..seedCallFrames([
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([4, 5])
        ]);

      // Upcast to the interface to prove the implements relationship holds.
      final CallFrameSource source = CallFrameTransport(gateway);

      final count = await _countFrames(source);

      expect(count, 2);
    });
  });
}
