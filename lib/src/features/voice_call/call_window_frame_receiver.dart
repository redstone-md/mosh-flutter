import 'dart:async';
import 'dart:io';

import 'call_video_frame.dart';
import 'call_video_renderer.dart';
import 'call_window_frame_channel.dart';
import 'call_window_input.dart';

/// A renderer receives pixels; it starts no media or capture runtime.
class CallWindowFrameReceiver {
  CallWindowFrameReceiver(this.renderer, this.acknowledge);
  final CallVideoRenderer renderer;
  final Future<void> Function(Map<String, Object?>) acknowledge;
  Socket? _socket;
  CallWindowInput? _input;
  StreamSubscription<String>? _lines;
  Map<String, int>? _profile;
  bool _closed = false;
  bool _connecting = false;

  Future<void> connect(int port, String token) async {
    if (_closed || _connecting || _socket != null) {
      throw StateError('Renderer stream already bound');
    }
    _connecting = true;
    try {
      final socket = await CallWindowFrameChannel.connect(port, token);
      if (_closed) {
        socket.destroy();
        return;
      }
      _socket = socket;
      _input = CallWindowInput(socket, _receive,
          onProfile: Platform.environment['MOSH_CALL_FRAME_PROFILE'] == '1'
              ? (value) => _profile = value
              : null);
      _lines = _input!.lines.listen((_) => socket.destroy(),
          onDone: () => renderer.update(null),
          onError: (Object _) => socket.destroy());
    } finally {
      _connecting = false;
    }
  }

  void _receive(CallVideoFrame frame) {
    if (_closed) return;
    final profile = _profile;
    unawaited(() async {
      final elapsed = Stopwatch()..start();
      try {
        await renderer.receive(frame);
      } catch (_) {/* Drop a failed GPU decode. */}
      await acknowledge({
        'sessionId': frame.sessionId,
        'callId': frame.callId,
        'sequence': frame.sequence,
        'local': frame.local,
        if (Platform.environment['MOSH_CALL_FRAME_PROFILE'] == '1')
          'profile': {
            'decodeMs': elapsed.elapsedMilliseconds,
            'arrivalAgeMs': frame.sourceAgeMs,
            ...?profile
          },
      });
    }()
        .catchError((Object _) {}));
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _socket?.destroy();
    await _lines?.cancel();
    await _input?.dispose();
    renderer.update(null);
  }
}
